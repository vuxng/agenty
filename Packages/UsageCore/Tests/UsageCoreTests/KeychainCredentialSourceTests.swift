import Foundation
import Security
import Testing
@testable import UsageCore

@Suite struct KeychainCredentialSourceTests {
    private let service = "io.github.vuxng.Agenty.tests.nonexistent"
    private let json = #"{"claudeAiOauth":{"accessToken":"test-token","expiresAt":1793790000000,"subscriptionType":"pro"}}"#
    private let expected = ClaudeCredential(accessToken: "test-token",
        expiresAt: Date(timeIntervalSince1970: 1_793_790_000), subscriptionType: "pro")

    @Test func plainJSONRunsSecurityAndFinishesInput() async throws {
        let channel = ScriptedChannel(lines: ["  " + json, "\t"])
        let runner = FakeProcessRunner(channel: channel)
        let source = KeychainCredentialSource(service: service, runner: runner)
        #expect(try await source.load() == expected)
        #expect(runner.executable == URL(filePath: "/usr/bin/security"))
        #expect(runner.arguments == ["find-generic-password", "-s", service, "-w"])
        #expect(runner.environment.isEmpty)
        #expect(channel.inputFinished)
    }

    @Test func hexJSONDecodes() async throws {
        let hex = json.utf8.map { String(format: "%02x", $0) }.joined()
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: [hex]))
        #expect(try await KeychainCredentialSource(service: service, runner: runner).load() == expected)
    }

    @Test func joinsAllOutputLines() async throws {
        let channel = ScriptedChannel(lines: ["{", String(json.dropFirst())])
        #expect(try await KeychainCredentialSource(service: service,
            runner: FakeProcessRunner(channel: channel)).load() == expected)
    }

    @Test func missingItemReturnsNilWithoutDenyingGate() async throws {
        let gate = KeychainAccessGate()
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: []))
        runner.exitCode = 44
        #expect(try await KeychainCredentialSource(service: service, gate: gate, runner: runner).load() == nil)
        #expect(!gate.isDenied)
    }

    @Test(arguments: [Int32(128), 51, 36])
    func accessFailureClassification(_ code: Int32) async {
        let gate = KeychainAccessGate()
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: []))
        runner.exitCode = code
        let status = code == 128 ? errSecUserCanceled : code == 51 ? errSecAuthFailed : errSecInteractionNotAllowed
        let source = KeychainCredentialSource(service: service, gate: gate, runner: runner)
        await #expect(throws: CredentialSourceError.accessDenied(status)) { try await source.load() }
        #expect(gate.isDenied == (code != 36))
        if code == 36 {
            await #expect(throws: CredentialSourceError.accessDenied(status)) { try await source.load() }
            #expect(runner.runCount == 2)
        }
    }

    @Test(arguments: ["", "garbage", "abc", "zz", "7b7d", "{}"])
    func invalidOutputIsUnreadable(_ output: String) async {
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: [output]))
        await #expect(throws: CredentialSourceError.unreadable) {
            try await KeychainCredentialSource(service: service, runner: runner).load()
        }
    }

    @Test func unknownExitIsUnreadableEvenWithValidOutput() async {
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: [json]))
        runner.exitCode = 1
        await #expect(throws: CredentialSourceError.unreadable) {
            try await KeychainCredentialSource(service: service, runner: runner).load()
        }
    }

    @Test func launchFailureIsUnavailable() async {
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: []))
        runner.launchError = CocoaError(.executableNotLoadable)
        await #expect(throws: CredentialSourceError.unavailable) {
            try await KeychainCredentialSource(service: service, runner: runner).load()
        }
    }

    @Test func signalTerminationIsUnavailable() async {
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: []))
        runner.launchError = ProcessRunnerError.unsuccessfulExit(code: nil)
        await #expect(throws: CredentialSourceError.unavailable) {
            try await KeychainCredentialSource(service: service, runner: runner).load()
        }
    }

    @Test func timeoutIsUnavailable() async {
        let channel = ScriptedChannel(lines: [])
        channel.hangsWhenEmpty = true
        let runner = FakeProcessRunner(channel: channel)
        await #expect(throws: CredentialSourceError.unavailable) {
            try await KeychainCredentialSource(service: service, runner: runner, timeout: .milliseconds(20)).load()
        }
    }

    @Test func deniedGateShortCircuitsRunner() async {
        let gate = KeychainAccessGate()
        gate.markDenied()
        let runner = FakeProcessRunner(channel: ScriptedChannel(lines: []))
        await #expect(throws: CredentialSourceError.accessDenied(errSecUserCanceled)) {
            try await KeychainCredentialSource(service: service, gate: gate, runner: runner).load()
        }
        #expect(runner.runCount == 0)
    }

    @Test func realSecurityMissingItemReturnsNil() async throws {
        // Only query this nonexistent service; never access an actual credential item.
        let source = KeychainCredentialSource(service: "io.github.vuxng.Agenty.tests.nonexistent",
            runner: SubprocessRunner())
        #expect(try await source.load() == nil)
    }
}
