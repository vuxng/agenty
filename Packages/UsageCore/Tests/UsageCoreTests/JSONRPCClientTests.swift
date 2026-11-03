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

    @Test func idsIncrementAndNotifyHasNoID() async throws {
        let ch = ScriptedChannel { req in req["id"].map { [#"{"id":\#($0.intValue!),"result":{}}"#] } ?? [] }
        let rpc = JSONRPCClient(channel: ch, includesVersionField: false)
        _ = try await rpc.call("a", params: .null)
        try await rpc.notify("initialized", params: nil)
        _ = try await rpc.call("b", params: .null)
        #expect(ch.sent.map { $0["id"] } == [.number(1), nil, .number(2)])
        #expect(ch.sent[1] == .object(["method": .string("initialized")]))
    }
}
