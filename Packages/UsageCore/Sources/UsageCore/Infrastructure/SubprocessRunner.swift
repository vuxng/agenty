import Foundation
import Subprocess
import System

/// `ProcessRunner` backed by swift-subprocess. Cancelling the surrounding task
/// terminates the child (SIGTERM, then SIGKILL after 3 s).
public struct SubprocessRunner: ProcessRunner {
    public init() {}

    public func run<R: Sendable>(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        body: @Sendable (any LineChannel) async throws -> R
    ) async throws -> R {
        var platformOptions = PlatformOptions()
        platformOptions.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(3))]
        var added: [Environment.Key: String?] = [:]
        for (key, value) in environment { added[Environment.Key(stringLiteral: key)] = value }
        let result = try await Subprocess.run(
            .path(FilePath(executable.path)),
            arguments: Arguments(arguments),
            environment: .inherit.updating(added),
            platformOptions: platformOptions,
            input: .inputWriter,
            output: .sequence,
            error: .discarded
        ) { execution in
            let channel = Channel(
                writer: execution.standardInputWriter,
                lines: execution.standardOutput.strings().makeAsyncIterator()
            )
            return try await body(channel)
        }
        return result.closureResult
    }
}

private final class Channel<Lines: AsyncIteratorProtocol>: LineChannel, @unchecked Sendable where Lines.Element == String {
    // @unchecked Sendable: the channel only lives inside the `run` body, and
    // callers drive it sequentially (one receive at a time), so the iterator is
    // never accessed concurrently.
    private let writer: StandardInputWriter
    private var lines: Lines

    init(writer: StandardInputWriter, lines: Lines) {
        self.writer = writer
        self.lines = lines
    }

    func send(_ line: String) async throws {
        _ = try await writer.write(line + "\n")
    }

    func receive() async throws -> String? {
        try await lines.next()
    }

    func finishInput() async throws {
        try await writer.finish()
    }
}
