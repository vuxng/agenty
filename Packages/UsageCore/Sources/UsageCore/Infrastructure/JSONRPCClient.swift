import Foundation
import Synchronization

public enum JSONRPCError: Error, Sendable, Equatable {
    case server(code: Int, message: String, data: JSONValue? = nil)
    case closed
}

/// Minimal JSON-RPC client over a `LineChannel`: one JSON message per line.
public final class JSONRPCClient: Sendable {
    private let channel: any LineChannel
    private let includesVersionField: Bool
    private let nextID = Mutex(1)

    public init(channel: any LineChannel, includesVersionField: Bool) {
        self.channel = channel
        self.includesVersionField = includesVersionField
    }

    /// Sends a request and returns the raw JSON of the response's `result`.
    public func call(_ method: String, params: JSONValue) async throws -> Data {
        let id = nextID.withLock { value -> Int in
            defer { value += 1 }
            return value
        }
        var message: [String: JSONValue] = ["id": .number(Double(id)), "method": .string(method)]
        if params != .null { message["params"] = params }
        try await send(message)

        while let line = try await channel.receive() {
            guard let reply = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
                  case .object = reply,
                  reply["method"] == nil,
                  reply["id"]?.intValue == id else { continue }
            if case .object(let error)? = reply["error"] {
                throw JSONRPCError.server(
                    code: error["code"]?.intValue ?? 0,
                    message: { if case .string(let s)? = error["message"] { return s } else { return "" } }(),
                    data: error["data"]
                )
            }
            return try JSONEncoder().encode(reply["result"] ?? .null)
        }
        throw JSONRPCError.closed
    }

    public func notify(_ method: String, params: JSONValue?) async throws {
        var message: [String: JSONValue] = ["method": .string(method)]
        if let params { message["params"] = params }
        try await send(message)
    }

    private func send(_ fields: [String: JSONValue]) async throws {
        var message = fields
        if includesVersionField { message["jsonrpc"] = .string("2.0") }
        let data = try JSONEncoder().encode(JSONValue.object(message))
        try await channel.send(String(decoding: data, as: UTF8.self))
    }
}
