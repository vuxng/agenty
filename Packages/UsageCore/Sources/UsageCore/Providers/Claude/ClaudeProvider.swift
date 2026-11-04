import Foundation
import os

public struct ClaudeProvider: UsageProvider {
    public let id: ProviderID = .claude

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let log = Logger(subsystem: "io.github.vuxng.Agenty", category: "claude")

    private let sources: [any CredentialSource]
    private let http: any HTTPClient
    private let now: @Sendable () -> Date

    public init(
        sources: [any CredentialSource],
        http: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sources = sources
        self.http = http
        self.now = now
    }

    public func fetch() async throws(UsageError) -> UsageSnapshot {
        let (best, keychainDenied) = bestCredential()
        guard let credential = best else { throw keychainDenied ? .keychainDenied : .notLoggedIn }
        if let expiresAt = credential.expiresAt, expiresAt <= now() {
            throw keychainDenied ? .keychainDenied : .tokenExpired
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let started = ContinuousClock.now
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            Self.log.error("claude request failed after \(started.duration(to: .now), privacy: .public)")
            throw .network(retryAfter: nil)
        }
        let status = response.statusCode
        Self.log.info("claude status \(status, privacy: .public) in \(started.duration(to: .now), privacy: .public)")

        switch status {
        case 200:
            let windows = try ClaudeUsageParser.windows(from: data)
            return UsageSnapshot(
                provider: .claude,
                plan: credential.plan,
                windows: windows,
                credits: nil,
                fetchedAt: now()
            )
        case 401, 403:
            throw .tokenExpired
        case 429:
            throw .network(retryAfter: Self.retryAfter(response))
        case 500...599:
            throw .network(retryAfter: nil)
        default:
            throw .unexpectedFormat("HTTP \(status)")
        }
    }

    /// Largest `expiresAt` wins, `nil` sorts lowest, ties keep the earlier source.
    /// Also reports whether any source was refused Keychain access.
    private func bestCredential() -> (credential: ClaudeCredential?, keychainDenied: Bool) {
        var best: ClaudeCredential?
        var keychainDenied = false
        for source in sources {
            let loaded: ClaudeCredential?
            do {
                loaded = try source.load()
            } catch let error as CredentialSourceError {
                switch error {
                case let .accessDenied(status):
                    if KeychainAccessGate.isDenial(status) { keychainDenied = true }
                    Self.log.error("claude credential source denied, OSStatus \(status, privacy: .public)")
                case .unreadable: Self.log.error("claude credential source unreadable")
                }
                continue
            } catch {
                Self.log.error("claude credential source failed")
                continue
            }
            guard let candidate = loaded else { continue }
            guard let current = best else { best = candidate; continue }
            if (candidate.expiresAt ?? .distantPast) > (current.expiresAt ?? .distantPast) { best = candidate }
        }
        return (best, keychainDenied)
    }

    /// Only a non-negative integer number of seconds is honoured; HTTP-dates are ignored.
    private static func retryAfter(_ response: HTTPURLResponse) -> Duration? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }),
              let seconds = Int(raw) else { return nil }
        return .seconds(seconds)
    }
}
