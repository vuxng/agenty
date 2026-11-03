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
                              clientVersion: "0.1.0", timeout: timeout, now: { Date(timeIntervalSince1970: 7) })
        return (p, runner)
    }

    private static func respond(_ msg: JSONValue) -> [String] {
        switch msg["method"] {
        case .string("initialize"): return [#"{"id":1,"result":{}}"#]
        case .string("account/rateLimits/read"): return [resultLine]
        default: return []
        }
    }

    @Test func handshakeOrderAndParams() async throws {
        let ch = ScriptedChannel { Self.respond($0) }
        let (p, runner) = provider(ch)
        let snap = try await p.fetch()
        #expect(snap.provider == .codex)
        #expect(snap.windows == [UsageWindow(kind: .session5h, usedPercent: 42, resetsAt: Date(timeIntervalSince1970: 100))])
        #expect(snap.fetchedAt == Date(timeIntervalSince1970: 7))
        #expect(ch.sent.map { $0["method"] } == [.string("initialize"), .string("initialized"), .string("account/rateLimits/read")])
        #expect(ch.sent[0]["params"] == .object(["clientInfo": .object([
            "name": .string("llmusage"), "title": .string("LLMUsage"), "version": .string("0.1.0")])]))
        #expect(ch.sent[2]["params"] == .object(["excludeResetCreditDetails": .bool(true)]))
        #expect(ch.sent.allSatisfy { $0["jsonrpc"] == nil })
        #expect(ch.inputFinished)
        #expect(runner.executable?.path == Self.path)
        #expect(runner.arguments == ["app-server"])
        #expect(runner.environment.isEmpty)
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
}
