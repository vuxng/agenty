import Foundation
import os
import Synchronization

/// Reads usage from `grok agent` (line-delimited JSON-RPC). Grok owns its own auth.
public struct GrokProvider: UsageProvider {
    public let id: ProviderID = .grok
    public let minimumInterval: Duration = .seconds(300)

    private static let log = Logger(subsystem: "io.github.vuxng.Agenty", category: "grok")

    private let locator: CLILocator
    private let pathOverride: @Sendable () -> String?
    private let runner: any ProcessRunner
    private let home: URL
    private let timeout: Duration
    private let now: @Sendable () -> Date

    public init(
        locator: CLILocator,
        pathOverride: @escaping @Sendable () -> String?,
        runner: any ProcessRunner,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: Duration = .seconds(15),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.locator = locator
        self.pathOverride = pathOverride
        self.runner = runner
        self.home = home
        self.timeout = timeout
        self.now = now
    }

    public func fetch() async throws(UsageError) -> UsageSnapshot {
        let started = ContinuousClock.now
        do {
            let snapshot = try await fetchOnce()
            Self.log.info("grok fetched in \(started.duration(to: .now), privacy: .public)")
            return snapshot
        } catch {
            Self.log.error("grok failed after \(started.duration(to: .now), privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func fetchOnce() async throws(UsageError) -> UsageSnapshot {
        guard let executable = await locator.locate("grok", override: pathOverride()) else {
            throw .cliNotFound
        }
        let runner = self.runner
        let fetchedAt = now()
        let environment = ["PATH": CodexProvider.searchPath(executable: executable, home: home)]
        let bodyStarted = Mutex(false)
        do {
            return try await withTimeout(timeout) {
                try await runner.run(executable: executable, arguments: ["agent", "--no-leader", "stdio"], environment: environment) { channel in
                    bodyStarted.withLock { $0 = true }
                    let rpc = JSONRPCClient(channel: channel, includesVersionField: true)
                    _ = try await rpc.call("initialize", params: .object([
                        "protocolVersion": .number(1), "clientCapabilities": .object([:]),
                    ]))
                    let result = try await rpc.call("_x.ai/billing", params: .object([:]))
                    try await channel.finishInput()
                    return try GrokBillingMapper.snapshot(from: result, fetchedAt: fetchedAt)
                }
            }
        } catch let error as UsageError {
            throw error
        } catch is TimeoutError {
            throw .network(retryAfter: nil)
        } catch let error as JSONRPCError {
            switch error {
            case .closed:
                throw .unexpectedFormat("grok agent exited early")
            case let .server(code, _, _):
                switch code {
                case -32000: // ACP auth-required code.
                    throw .notLoggedIn
                case -32601:
                    throw .unexpectedFormat("grok billing method missing")
                case -32603:
                    throw .network(retryAfter: nil)
                default:
                    throw .unexpectedFormat("grok error \(code)")
                }
            }
        } catch is CancellationError {
            throw .network(retryAfter: nil)
        } catch {
            // Before the body ran this is a spawn failure; afterwards (EPIPE, output limit) the child died.
            if bodyStarted.withLock({ $0 }) { throw .unexpectedFormat("grok agent exited early") }
            throw .cliNotFound
        }
    }
}
