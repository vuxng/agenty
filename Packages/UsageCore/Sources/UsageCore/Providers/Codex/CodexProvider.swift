import Foundation
import os

/// Reads plan limits from `codex app-server` (line-delimited JSON-RPC). Codex owns its own token.
public struct CodexProvider: UsageProvider {
    public let id: ProviderID = .codex

    private static let log = Logger(subsystem: "io.github.vuxng.LLMUsage", category: "codex")

    private let locator: CLILocator
    private let pathOverride: @Sendable () -> String?
    private let runner: any ProcessRunner
    private let clientVersion: String
    private let timeout: Duration
    private let now: @Sendable () -> Date

    public init(
        locator: CLILocator,
        pathOverride: @escaping @Sendable () -> String?,
        runner: any ProcessRunner,
        clientVersion: String,
        timeout: Duration = .seconds(15),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.locator = locator
        self.pathOverride = pathOverride
        self.runner = runner
        self.clientVersion = clientVersion
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
        do {
            return try await withTimeout(timeout) {
                try await runner.run(executable: executable, arguments: ["app-server"], environment: [:]) { channel in
                    let rpc = JSONRPCClient(channel: channel, includesVersionField: false)
                    _ = try await rpc.call("initialize", params: .object([
                        "clientInfo": .object([
                            "name": .string("llmusage"),
                            "title": .string("LLMUsage"),
                            "version": .string(version),
                        ]),
                    ]))
                    try await rpc.notify("initialized", params: nil)
                    let result = try await rpc.call("account/rateLimits/read",
                                                    params: .object(["excludeResetCreditDetails": .bool(true)]))
                    try await channel.finishInput()
                    return try CodexRateLimitsMapper.snapshot(from: result, fetchedAt: fetchedAt)
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
            case let .server(code, message):
                let lowered = message.lowercased()
                if ["auth", "login", "logged in"].contains(where: lowered.contains) { throw .notLoggedIn }
                throw .unexpectedFormat("codex error \(code)")
            }
        } catch {
            throw .cliNotFound
        }
    }
}
