import Foundation
import Testing
@testable import UsageCore

@Suite struct SubprocessRunnerTests {
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
            arguments: ["-c", "echo \"$LLMUSAGE_TEST\""], environment: ["LLMUSAGE_TEST": "ok"]) { try await $0.receive() }
        #expect(line == "ok")
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
}
