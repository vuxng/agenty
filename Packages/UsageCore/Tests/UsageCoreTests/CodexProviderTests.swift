import Foundation
import Testing
@testable import UsageCore

@Suite struct CodexProviderTests {
    private static let path = "/Users/test/.local/bin/codex"

    private func locator(found: Bool = true) -> CLILocator {
        CLILocator(home: URL(filePath: "/Users/test"),
                   probe: FakeProbe(executables: found ? [Self.path] : []),
                   shell: FakeShell(result: nil))
    }

    private static let resultLine = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":100},"planType":"pro"}}}"#

    private func provider(_ channel: ScriptedChannel, found: Bool = true, timeout: Duration = .seconds(5))
        -> (CodexProvider, FakeProcessRunner) {
        let runner = FakeProcessRunner(channel: channel)
        let p = CodexProvider(locator: locator(found: found), pathOverride: { nil }, runner: runner,
                              clientVersion: "0.1.0", home: URL(filePath: "/Users/test"),
                              timeout: timeout, now: { Date(timeIntervalSince1970: 7) })
        return (p, runner)
    }

    private static func respond(_ msg: JSONValue) -> [String] {
        switch msg["method"] {
        case .string("initialize"): return [#"{"id":1,"result":{}}"#]
        case .string("account/rateLimits/read"): return [resultLine]
        case .string("account/read"): return [accountLine]
        default: return []
        }
    }

    private static let accountLine = #"{"id":3,"result":{"account":{"type":"chatgpt","email":"user@example.com","planType":"pro"},"requiresOpenaiAuth":true}}"#

    @Test func handshakeOrderAndParams() async throws {
        let ch = ScriptedChannel { Self.respond($0) }
        let (p, runner) = provider(ch)
        let snap = try await p.fetch()
        #expect(snap.provider == .codex)
        #expect(snap.windows == [UsageWindow(kind: .session5h, usedPercent: 42, resetsAt: Date(timeIntervalSince1970: 100))])
        #expect(snap.fetchedAt == Date(timeIntervalSince1970: 7))
        #expect(ch.sent.map { $0["method"] } == [.string("initialize"), .string("initialized"),
                                                .string("account/rateLimits/read"), .string("account/read")])
        #expect(ch.sent[0]["params"] == .object(["clientInfo": .object([
            "name": .string("agenty"), "title": .string("Agenty"), "version": .string("0.1.0")])]))
        #expect(ch.sent[2]["params"] == .object(["excludeResetCreditDetails": .bool(true)]))
        try #require(ch.sent.count == 4)
        #expect(ch.sent[3]["params"] == .object([:]))
        #expect(snap.accountEmail == "user@example.com")
        #expect(ch.sent.allSatisfy { $0["jsonrpc"] == nil })
        #expect(ch.inputFinished)
        #expect(runner.executable?.path == Self.path)
        #expect(runner.arguments == ["app-server"])
        #expect(runner.environment.keys.sorted() == ["PATH"])
        let path = try #require(runner.environment["PATH"])
        #expect(path.hasPrefix("/Users/test/.local/bin:"))
        #expect(path.contains("/opt/homebrew/bin"))
        let entries = path.split(separator: ":").map(String.init)
        #expect(entries.count == Set(entries).count)
        #expect(p.id == .codex)
    }

    @Test func notificationsBeforeResponse() async throws {
        let ch = ScriptedChannel { msg in
            switch msg["method"] {
            case .string("initialize"): return [#"{"id":1,"result":{}}"#]
            case .string("account/rateLimits/read"): return [#"{"method":"account/updated","params":{}}"#, Self.resultLine]
            default: return []
            }
        }
        let snap = try await provider(ch).0.fetch()
        #expect(snap.plan == "pro")
    }

    @Test func accountReadErrorStillReturnsSnapshot() async throws {
        let ch = ScriptedChannel { msg in
            switch msg["method"] {
            case .string("account/read"): return [#"{"id":3,"error":{"code":-32000,"message":"Not logged in"}}"#]
            default: return Self.respond(msg)
            }
        }
        let snap = try await provider(ch).0.fetch()
        #expect(snap.windows.count == 1)
        #expect(snap.accountEmail == nil)
    }

    @Test func accountReadWithoutReplyStillReturnsSnapshot() async throws {
        let ch = ScriptedChannel { msg in msg["method"] == .string("account/read") ? [] : Self.respond(msg) }
        let snap = try await provider(ch).0.fetch()
        #expect(snap.accountEmail == nil)
        #expect(ch.inputFinished)
    }

    @Test func cliMissingIsCliNotFound() async {
        let ch = ScriptedChannel { _ in [] }
        let (p, runner) = provider(ch, found: false)
        await #expect(throws: UsageError.cliNotFound) { try await p.fetch() }
        #expect(runner.runCount == 0)
    }

    @Test func authErrorIsNotLoggedIn() async {
        let ch = ScriptedChannel { _ in [#"{"id":1,"error":{"code":-32000,"message":"Not logged in"}}"#] }
        await #expect(throws: UsageError.notLoggedIn) { try await provider(ch).0.fetch() }
    }

    @Test func otherRPCErrorIsUnexpectedFormat() async {
        let ch = ScriptedChannel { _ in [#"{"id":1,"error":{"code":-32603,"message":"boom"}}"#] }
        await #expect(throws: UsageError.unexpectedFormat("codex error -32603")) { try await provider(ch).0.fetch() }
    }

    @Test func earlyExitIsUnexpectedFormat() async {
        let ch = ScriptedChannel { _ in [] }
        await #expect(throws: UsageError.unexpectedFormat("codex app-server exited early")) { try await provider(ch).0.fetch() }
    }

    @Test func timeoutIsNetwork() async {
        let ch = ScriptedChannel { _ in [] }
        ch.hangsWhenEmpty = true
        await #expect(throws: UsageError.network(retryAfter: nil)) {
            try await provider(ch, timeout: .milliseconds(100)).0.fetch()
        }
    }

    @Test func mapperErrorPassesThrough() async {
        let ch = ScriptedChannel { msg in
            msg["method"] == .string("initialize") ? [#"{"id":1,"result":{}}"#] : [#"{"id":2,"result":{"rateLimits":null}}"#]
        }
        await #expect(throws: UsageError.notLoggedIn) { try await provider(ch).0.fetch() }
    }

    @Test func cancellationIsNetwork() async {
        let ch = ScriptedChannel { _ in [] }
        ch.hangsWhenEmpty = true
        let (p, _) = provider(ch)
        let task = Task { () -> UsageError? in
            do throws(UsageError) { _ = try await p.fetch(); return nil } catch { return error }
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        #expect(await task.value == .network(retryAfter: nil))
    }

    @Test func writeFailureAfterStartIsUnexpectedFormat() async {
        let ch = ScriptedChannel { _ in [] }
        ch.sendError = POSIXError(.EPIPE)
        await #expect(throws: UsageError.unexpectedFormat("codex app-server exited early")) { try await provider(ch).0.fetch() }
    }

    @Test func launchFailureIsCliNotFound() async {
        let ch = ScriptedChannel { _ in [] }
        let (p, runner) = provider(ch)
        runner.launchError = POSIXError(.ENOENT)
        await #expect(throws: UsageError.cliNotFound) { try await p.fetch() }
    }
}
