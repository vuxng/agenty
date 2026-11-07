import Foundation
import Testing
@testable import UsageCore

@Suite struct SubprocessRunnerTests {
    @Test func nonzeroExitStillReturnsOutputByDefault() async throws {
        let output = try await SubprocessRunner().run(executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", "echo ok; exit 3"], environment: [:]) { channel in
                try await channel.finishInput()
                var lines: [String] = []
                while let line = try await channel.receive() { lines.append(line) }
                return lines
            }
        #expect(output == ["ok"])
    }

    @Test func checkedRunRejectsNonzeroExitAfterOutput() async throws {
        await #expect(throws: ProcessRunnerError.unsuccessfulExit(code: 3)) {
            try await SubprocessRunner().run(executable: URL(filePath: "/bin/sh"),
                arguments: ["-c", "echo ok; exit 3"], environment: [:], requireSuccessfulExit: true) { channel in
                    try await channel.finishInput()
                    var lines: [String] = []
                    while let line = try await channel.receive() { lines.append(line) }
                    #expect(lines == ["ok"])
                    return lines
                }
        }
    }

    @Test func signalTerminationHasNoExitCode() async {
        await #expect(throws: ProcessRunnerError.unsuccessfulExit(code: nil)) {
            try await SubprocessRunner().run(executable: URL(filePath: "/bin/sh"),
                arguments: ["-c", "kill -TERM $$"], environment: [:], requireSuccessfulExit: true) { channel in
                    try await channel.finishInput()
                    while try await channel.receive() != nil {}
                }
        }
    }

    @Test func checkedRunReturnsOutputOnSuccess() async throws {
        let output = try await SubprocessRunner().run(executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", "echo ok; exit 0"], environment: [:], requireSuccessfulExit: true) { channel in
                try await channel.finishInput()
                var lines: [String] = []
                while let line = try await channel.receive() { lines.append(line) }
                return lines
            }
        #expect(output == ["ok"])
    }

    @Test func echoesLinesThroughCat() async throws {
        let out = try await SubprocessRunner().run(executable: URL(filePath: "/bin/cat"), arguments: [], environment: [:]) { ch in
            try await ch.send("hello")
            let first = try await ch.receive()
            try await ch.finishInput()
            let eof = try await ch.receive()
            return [first, eof]
        }
        #expect(out == ["hello", nil])
    }

    @Test func passesExtraEnvironment() async throws {
        let line = try await SubprocessRunner().run(executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", "echo \"$AGENTY_TEST\""], environment: ["AGENTY_TEST": "ok"]) { try await $0.receive() }
        #expect(line == "ok")
    }

    @Test func longLineArrivesWhole() async throws {
        let line = try await SubprocessRunner().run(executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", "head -c 300000 /dev/zero | tr '\\0' a; echo"], environment: [:]) { try await $0.receive() }
        #expect(line == String(repeating: "a", count: 300000))
    }

    @Test func launchFailureThrows() async {
        await #expect(throws: (any Error).self) {
            try await SubprocessRunner().run(executable: URL(filePath: "/nonexistent/codex"), arguments: [], environment: [:]) { _ in 0 }
        }
    }

    @Test func timeoutTerminatesProcess() async {
        let start = ContinuousClock.now
        await #expect(throws: TimeoutError()) {
            try await withTimeout(.milliseconds(200)) {
                try await SubprocessRunner().run(executable: URL(filePath: "/bin/sleep"), arguments: ["30"], environment: [:]) { try await $0.receive() }
            }
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func writeToExitedChildThrowsInsteadOfSIGPIPE() async throws {
        let threw = try await withTimeout(.seconds(5)) {
            try await SubprocessRunner().run(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "exit 0"], environment: [:]) { ch in
                while try await ch.receive() != nil {}
                // Give the kernel a moment to close the read end of the pipe.
                try await Task.sleep(for: .milliseconds(100))
                do {
                    try await ch.send("x")
                    return false
                } catch {
                    return true
                }
            }
        }
        #expect(threw)
    }
}
