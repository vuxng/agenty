import Foundation
import Subprocess
import Synchronization
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
    // @unchecked Sendable: the channel only lives inside the `run` body and the
    // iterator is not Sendable. The single-caller contract (one receive at a time,
    // one send/finishInput at a time) is enforced by the busy flags below, which
    // trap on concurrent use instead of racing.
    private let writer: StandardInputWriter
    private var lines: Lines
    private let receiving = Mutex(false)
    private let sending = Mutex(false)

    init(writer: StandardInputWriter, lines: Lines) {
        self.writer = writer
        self.lines = lines
    }

    private static func enter(_ flag: borrowing Mutex<Bool>, _ message: String) {
        let wasBusy = flag.withLock { busy in
            defer { busy = true }
            return busy
        }
        if wasBusy { preconditionFailure(message) }
    }

    func send(_ line: String) async throws {
        Self.enter(sending, "SubprocessLineChannel.send() called concurrently")
        defer { sending.withLock { $0 = false } }
        _ = try await writer.write(line + "\n")
    }

    func receive() async throws -> String? {
        Self.enter(receiving, "SubprocessLineChannel.receive() called concurrently")
        defer { receiving.withLock { $0 = false } }
        return try await lines.next()
    }

    func finishInput() async throws {
        Self.enter(sending, "SubprocessLineChannel.finishInput() called concurrently")
        defer { sending.withLock { $0 = false } }
        try await writer.finish()
    }
}
