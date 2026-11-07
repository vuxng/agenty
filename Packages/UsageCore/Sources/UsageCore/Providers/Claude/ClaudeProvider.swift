import Foundation
import os
import Synchronization

public struct ClaudeProvider: UsageProvider {
    public let id: ProviderID = .claude

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let profileEndpoint = URL(string: "https://api.anthropic.com/api/oauth/profile")!
    private static let log = Logger(subsystem: "io.github.vuxng.Agenty", category: "claude")

    private let sources: [any CredentialSource]
    private let http: any HTTPClient
    private let now: @Sendable () -> Date
    private let profileCache = ProfileCache()

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
        let (best, keychainDenied) = await bestCredential()
        // A cancelled Keychain read looks like a missing credential; report it as transient instead.
        if Task.isCancelled { throw .network(retryAfter: nil) }
        guard let credential = best else { throw keychainDenied ? .keychainDenied : .notLoggedIn }
        if let expiresAt = credential.expiresAt, expiresAt <= now() {
            throw keychainDenied ? .keychainDenied : .tokenExpired
        }

        let started = ContinuousClock.now
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.data(for: Self.request(Self.endpoint, token: credential.accessToken))
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
                fetchedAt: now(),
                accountEmail: await accountEmail(token: credential.accessToken)
            )
        case 401, 403:
            throw .tokenExpired
        case 429:
            let header = response.value(forHTTPHeaderField: "Retry-After") ?? "none"
            Self.log.notice("claude rate limited, Retry-After: \(header, privacy: .public)")
            throw .rateLimited(retryAfter: Self.retryAfter(response))
        case 500...599:
            throw .network(retryAfter: nil)
        default:
            throw .unexpectedFormat("HTTP \(status)")
        }
    }

    /// Fetched once per access token. A failed lookup is retried on the next fetch and never fails the snapshot.
    private func accountEmail(token: String) async -> String? {
        if let cached = profileCache.lookup(token) { return cached.email }
        guard let (data, response) = try? await http.data(for: Self.request(Self.profileEndpoint, token: token)) else {
            Self.log.notice("claude profile request failed")
            return nil
        }
        guard response.statusCode == 200 else {
            Self.log.notice("claude profile status \(response.statusCode, privacy: .public)")
            return nil
        }
        let email = Self.email(fromProfile: data)
        profileCache.store(ProfileCache.Entry(token: token, email: email))
        return email
    }

    private static func email(fromProfile data: Data) -> String? {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let email = (root?["account"] as? [String: Any])?["email"] as? String, !email.isEmpty else { return nil }
        return email
    }

    private static func request(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Largest `expiresAt` wins, `nil` sorts lowest, ties keep the earlier source.
    /// Also reports whether any source was refused Keychain access.
    private func bestCredential() async -> (credential: ClaudeCredential?, keychainDenied: Bool) {
        var best: ClaudeCredential?
        var keychainDenied = false
        for source in sources {
            let loaded: ClaudeCredential?
            do {
                loaded = try await source.load()
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

/// The profile email for the last access token seen, so `/api/oauth/profile` is hit once per token.
private final class ProfileCache: Sendable {
    struct Entry {
        let token: String
        let email: String?
    }

    private let entry = Mutex<Entry?>(nil)

    func lookup(_ token: String) -> Entry? { entry.withLock { $0?.token == token ? $0 : nil } }
    func store(_ new: Entry) { entry.withLock { $0 = new } }
}
