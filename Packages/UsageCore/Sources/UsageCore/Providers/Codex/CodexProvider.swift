import Foundation
import os
import Synchronization

/// Reads plan limits from `codex app-server` (line-delimited JSON-RPC). Codex owns its own token.
public struct CodexProvider: UsageProvider {
    public let id: ProviderID = .codex

    private static let log = Logger(subsystem: "io.github.vuxng.Agenty", category: "codex")

    private let locator: CLILocator
    private let pathOverride: @Sendable () -> String?
    private let runner: any ProcessRunner
    private let clientVersion: String
    private let home: URL
    private let timeout: Duration
    private let now: @Sendable () -> Date

    public init(
        locator: CLILocator,
        pathOverride: @escaping @Sendable () -> String?,
        runner: any ProcessRunner,
        clientVersion: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: Duration = .seconds(15),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.locator = locator
        self.pathOverride = pathOverride
        self.runner = runner
        self.clientVersion = clientVersion
        self.home = home
        self.timeout = timeout
        self.now = now
    }

    public func fetch() async throws(UsageError) -> UsageSnapshot {
        let started = ContinuousClock.now
        do {
            let snapshot = try await fetchOnce()
            Self.log.info("codex fetched in \(started.duration(to: .now), privacy: .public)")
            return snapshot
        } catch {
            Self.log.error("codex failed after \(started.duration(to: .now), privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func fetchOnce() async throws(UsageError) -> UsageSnapshot {
        guard let executable = await locator.locate("codex", override: pathOverride()) else {
            throw .cliNotFound
        }
        let runner = self.runner
        let version = clientVersion
        let fetchedAt = now()
        let environment = ["PATH": Self.searchPath(executable: executable, home: home)]
        let bodyStarted = Mutex(false)
        do {
            return try await withTimeout(timeout) {
                try await runner.run(executable: executable, arguments: ["app-server"], environment: environment) { channel in
                    bodyStarted.withLock { $0 = true }
                    let rpc = JSONRPCClient(channel: channel, includesVersionField: false)
                    try await CodexAppServer.initialize(rpc, version: version)
                    let result = try await rpc.call("account/rateLimits/read",
                                                    params: .object(["excludeResetCreditDetails": .bool(true)]))
                    // Best effort: a failed account lookup must not turn into "not logged in" for the whole card.
                    let account = try? await rpc.call("account/read", params: .object([:]))
                    try await channel.finishInput()
                    var snapshot = try CodexRateLimitsMapper.snapshot(from: result, fetchedAt: fetchedAt)
                    snapshot.accountEmail = account.flatMap(CodexAccountMapper.email(from:))
                    return snapshot
                }
            }
        } catch let error as UsageError {
            throw error
        } catch is TimeoutError {
            throw .network(retryAfter: nil)
        } catch let error as JSONRPCError {
            switch error {
            case .closed:
                throw .unexpectedFormat("codex app-server exited early")
            case let .server(code, message, _):
                let lowered = message.lowercased()
                if ["auth", "login", "logged in"].contains(where: lowered.contains) { throw .notLoggedIn }
                throw .unexpectedFormat("codex error \(code)")
            }
        } catch is CancellationError {
            throw .network(retryAfter: nil)
        } catch {
            // Before the body ran this is a spawn failure; afterwards (EPIPE, output limit) the child died.
            if bodyStarted.withLock({ $0 }) { throw .unexpectedFormat("codex app-server exited early") }
            throw .cliNotFound
        }
    }

    /// GUI apps inherit the launchd PATH, which lacks node for npm-installed codex shims.
    static func searchPath(executable: URL, home: URL, inherited: String? = ProcessInfo.processInfo.environment["PATH"]) -> String {
        let candidates = [
            executable.deletingLastPathComponent().path,
            home.appending(path: ".local/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ] + (inherited ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }
}
