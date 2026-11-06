import Foundation
import Synchronization
@testable import UsageCore

/// In-memory `LineChannel` for tests. Each sent line is parsed and handed to `responder`,
/// whose returned lines are queued for `receive()`.
final class ScriptedChannel: LineChannel, @unchecked Sendable {
    private struct State {
        var queue: [String]
        var sent: [JSONValue] = []
        var inputFinished = false
        var hangsWhenEmpty = false
        var sendError: (any Error)?
    }

    private let state: Mutex<State>
    private let responder: @Sendable (JSONValue) -> [String]

    init(responder: @escaping @Sendable (JSONValue) -> [String]) {
        self.state = Mutex(State(queue: []))
        self.responder = responder
    }

    init(lines: [String]) {
        self.state = Mutex(State(queue: lines))
        self.responder = { _ in [] }
    }

    var hangsWhenEmpty: Bool {
        get { state.withLock { $0.hangsWhenEmpty } }
        set { state.withLock { $0.hangsWhenEmpty = newValue } }
    }

    /// When set, `send` throws this error instead of recording the line.
    var sendError: (any Error)? {
        get { state.withLock { $0.sendError } }
        set { state.withLock { $0.sendError = newValue } }
    }

    var sent: [JSONValue] { state.withLock { $0.sent } }
    var inputFinished: Bool { state.withLock { $0.inputFinished } }

    func send(_ line: String) async throws {
        if let error = sendError { throw error }
        let value = (try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))) ?? .null
        let replies = responder(value)
        state.withLock {
            $0.sent.append(value)
            $0.queue.append(contentsOf: replies)
        }
    }

    func receive() async throws -> String? {
        let next: (line: String?, hang: Bool) = state.withLock {
            if $0.queue.isEmpty { return (nil, $0.hangsWhenEmpty) }
            return ($0.queue.removeFirst(), false)
        }
        if let line = next.line { return line }
        if next.hang {
            try await Task.sleep(for: .seconds(3600))
        }
        return nil
    }

    func finishInput() async throws {
        state.withLock { $0.inputFinished = true }
    }
}

/// `ProcessRunner` that hands the scripted channel to the body and records the call.
final class FakeProcessRunner: ProcessRunner, @unchecked Sendable {
    private struct Record {
        var executable: URL?
        var arguments: [String] = []
        var environment: [String: String] = [:]
        var runCount = 0
        var launchError: (any Error)?
        var exitCode: Int32 = 0
    }

    private let channel: ScriptedChannel
    private let record = Mutex(Record())

    init(channel: ScriptedChannel) { self.channel = channel }

    var executable: URL? { record.withLock { $0.executable } }
    var arguments: [String] { record.withLock { $0.arguments } }
    var environment: [String: String] { record.withLock { $0.environment } }
    /// When set, `run` throws this error before calling the body (a spawn failure).
    var launchError: (any Error)? {
        get { record.withLock { $0.launchError } }
        set { record.withLock { $0.launchError = newValue } }
    }
    var runCount: Int { record.withLock { $0.runCount } }

    var exitCode: Int32 {
        get { record.withLock { $0.exitCode } }
        set { record.withLock { $0.exitCode = newValue } }
    }

    func run<R: Sendable>(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        requireSuccessfulExit: Bool,
        body: @Sendable (any LineChannel) async throws -> R
    ) async throws -> R {
        let result = try await run(executable: executable, arguments: arguments, environment: environment, body: body)
        if requireSuccessfulExit && exitCode != 0 { throw ProcessRunnerError.unsuccessfulExit }
        return result
    }

    func run<R: Sendable>(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        body: @Sendable (any LineChannel) async throws -> R
    ) async throws -> R {
        record.withLock {
            $0.executable = executable
            $0.arguments = arguments
            $0.environment = environment
            $0.runCount += 1
        }
        if let error = launchError { throw error }
        return try await body(channel)
    }
}
