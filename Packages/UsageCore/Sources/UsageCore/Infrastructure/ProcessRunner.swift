import Foundation

/// A line-oriented duplex channel to a child process. `receive()` returns `nil` at EOF.
public protocol LineChannel: AnyObject, Sendable {
    func send(_ line: String) async throws
    func receive() async throws -> String?
    func finishInput() async throws
}

public protocol ProcessRunner: Sendable {
    /// `environment` holds variables added on top of the inherited environment.
    func run<R: Sendable>(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        body: @Sendable (any LineChannel) async throws -> R
    ) async throws -> R

    /// When requested, throws `ProcessRunnerError.unsuccessfulExit` after unsuccessful termination.
    func run<R: Sendable>(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        requireSuccessfulExit: Bool,
        body: @Sendable (any LineChannel) async throws -> R
    ) async throws -> R
}

public enum ProcessRunnerError: Error, Sendable, Equatable {
    case unsuccessfulExit
}
