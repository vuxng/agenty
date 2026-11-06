import Foundation
import Testing
@testable import UsageCore

@Suite struct JSONRPCClientTests {
    @Test func callSendsRequestWithoutVersionField() async throws {
        let ch = ScriptedChannel { _ in [#"{"id":1,"result":{"ok":true}}"#] }
        let rpc = JSONRPCClient(channel: ch, includesVersionField: false)
        _ = try await rpc.call("initialize", params: .object(["a": .number(1)]))
        #expect(ch.sent == [.object(["id": .number(1), "method": .string("initialize"), "params": .object(["a": .number(1)])])])
    }

    @Test func callIncludesVersionFieldWhenConfigured() async throws {
        let ch = ScriptedChannel { _ in [#"{"jsonrpc":"2.0","id":1,"result":{}}"#] }
        _ = try await JSONRPCClient(channel: ch, includesVersionField: true).call("x", params: .object([:]))
        #expect(ch.sent.first?["jsonrpc"] == .string("2.0"))
    }

    @Test func callSkipsNotificationsBeforeResponse() async throws {
        let ch = ScriptedChannel { _ in [#"{"method":"account/updated","params":{}}"#,
                                         #"{"method":"remoteControl/status/changed","params":{}}"#,
                                         #"{"id":1,"result":{"v":7}}"#] }
        let data = try await JSONRPCClient(channel: ch, includesVersionField: false).call("m", params: .null)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == .object(["v": .number(7)]))
    }

    @Test func callSkipsNonJSONLines() async throws {
        let ch = ScriptedChannel { _ in ["Update available: 1.0.71", #"{"id":1,"result":{}}"#] }
        _ = try await JSONRPCClient(channel: ch, includesVersionField: false).call("m", params: .null)
    }

    @Test func callMapsErrorObject() async {
        let ch = ScriptedChannel { _ in [#"{"id":1,"error":{"code":-32000,"message":"Authentication required"}}"#] }
        await #expect(throws: JSONRPCError.server(code: -32000, message: "Authentication required")) {
            try await JSONRPCClient(channel: ch, includesVersionField: false).call("m", params: .null)
        }
    }

    @Test func callThrowsClosedOnEOF() async {
        let ch = ScriptedChannel { _ in [] }
        await #expect(throws: JSONRPCError.closed) {
            try await JSONRPCClient(channel: ch, includesVersionField: false).call("m", params: .null)
        }
    }

    @Test func serverErrorCarriesData() async {
        let ch = ScriptedChannel { _ in [#"{"id":1,"error":{"code":-32600,"message":"m","data":{"config_write_error_code":"configVersionConflict"}}}"#] }
        await #expect(throws: JSONRPCError.server(
            code: -32600, message: "m",
            data: .object(["config_write_error_code": .string("configVersionConflict")])
        )) {
            try await JSONRPCClient(channel: ch, includesVersionField: false).call("m", params: .null)
        }
    }

    @Test func idsIncrementAndNotifyHasNoID() async throws {
        let ch = ScriptedChannel { req in req["id"].map { [#"{"id":\#($0.intValue!),"result":{}}"#] } ?? [] }
        let rpc = JSONRPCClient(channel: ch, includesVersionField: false)
        _ = try await rpc.call("a", params: .null)
        try await rpc.notify("initialized", params: nil)
        _ = try await rpc.call("b", params: .null)
        #expect(ch.sent.map { $0["id"] } == [.number(1), nil, .number(2)])
        #expect(ch.sent[1] == .object(["method": .string("initialized")]))
    }

    @Test func appServerSessionInitializesAndFinishesInput() async throws {
        let home = URL(filePath: "/Users/test")
        let ch = ScriptedChannel { request in
            switch request["method"] {
            case .string("initialize"): return [#"{"id":1,"result":{}}"#]
            case .string("config/read"): return [#"{"id":2,"result":{"ok":true}}"#]
            default: return []
            }
        }
        let runner = FakeProcessRunner(channel: ch)
        let server = CodexAppServer(
            locator: CLILocator(home: home, probe: FakeProbe(executables: ["/custom/bin/codex"]), shell: FakeShell(result: nil)),
            pathOverride: { "/custom/bin/codex" }, runner: runner, clientVersion: "0.1.0", home: home, timeout: .seconds(5))
        let data = try await server.withSession(environment: ["CODEX_HOME": "/tmp/agenty-test-codex"]) { rpc in
            #expect(ch.sent == [
                .object(["id": .number(1), "method": .string("initialize"), "params": .object([
                    "clientInfo": .object(["name": .string("agenty"), "title": .string("Agenty"), "version": .string("0.1.0")]),
                ])]),
                .object(["method": .string("initialized")]),
            ])
            #expect(!ch.inputFinished)
            return try await rpc.call("config/read", params: .null)
        }
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == .object(["ok": .bool(true)]))
        #expect(ch.inputFinished)
        #expect(runner.executable?.path == "/custom/bin/codex")
        #expect(runner.arguments == ["app-server"])
        #expect(runner.environment["CODEX_HOME"] == "/tmp/agenty-test-codex")
        #expect(runner.environment["PATH"]?.hasPrefix("/custom/bin:/Users/test/.local/bin:/opt/homebrew/bin:/usr/local/bin") == true)
    }

    @Test func appServerSessionMissingCLIThrows() async {
        let home = URL(filePath: "/Users/test")
        let runner = FakeProcessRunner(channel: ScriptedChannel { _ in [] })
        let server = CodexAppServer(
            locator: CLILocator(home: home, probe: FakeProbe(executables: []), shell: FakeShell(result: nil)),
            pathOverride: { nil }, runner: runner, clientVersion: "0.1.0", home: home, timeout: .seconds(5))
        await #expect(throws: CodexAppServerError.self) {
            try await server.withSession { _ in Issue.record("Body must not run without codex") }
        }
        #expect(runner.runCount == 0)
    }

    @Test(arguments: [true, false])
    func appServerSessionTimesOut(duringInitialize: Bool) async {
        let home = URL(filePath: "/Users/test")
        let ch = ScriptedChannel { _ in duringInitialize ? [] : [#"{"id":1,"result":{}}"#] }
        ch.hangsWhenEmpty = true
        let server = CodexAppServer(
            locator: CLILocator(home: home, probe: FakeProbe(executables: ["/Users/test/.local/bin/codex"]), shell: FakeShell(result: nil)),
            pathOverride: { nil }, runner: FakeProcessRunner(channel: ch), clientVersion: "0.1.0", home: home, timeout: .milliseconds(100))
        await #expect(throws: TimeoutError()) {
            try await server.withSession { _ in try await Task.sleep(for: .seconds(30)) }
        }
    }
}
