import Foundation
import Testing
@testable import UsageCore

@Suite struct GrokProviderTests {
    private static let path = "/Users/test/.grok/bin/grok"

    private func locator(found: Bool = true) -> CLILocator {
        CLILocator(home: URL(filePath: "/Users/test"),
                   probe: FakeProbe(executables: found ? [Self.path] : []),
                   shell: FakeShell(result: nil))
    }

    private func provider(_ channel: ScriptedChannel, found: Bool = true, timeout: Duration = .seconds(5))
        -> (GrokProvider, FakeProcessRunner) {
        let runner = FakeProcessRunner(channel: channel)
        let p = GrokProvider(locator: locator(found: found), pathOverride: { nil }, runner: runner,
                             home: URL(filePath: "/Users/test"), timeout: timeout,
                             now: { Date(timeIntervalSince1970: 7) })
        return (p, runner)
    }

    private static let resultLine = #"{"jsonrpc":"2.0","id":2,"result":{"config":{"creditUsagePercent":7,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-11-12T10:43:47.642+00:00"}},"subscription_tier":"SuperGrok Plus"}}"#

    private static func respond(_ msg: JSONValue) -> [String] {
        switch msg["method"] {
        case .string("initialize"): return [#"{"jsonrpc":"2.0","id":1,"result":{}}"#]
        case .string("_x.ai/billing"): return [resultLine]
        default: return []
        }
    }

    @Test func handshakeOrderAndParams() async throws {
        let ch = ScriptedChannel { Self.respond($0) }
        let (p, runner) = provider(ch)
        let snap = try await p.fetch()
        #expect(snap.provider == .grok)
        #expect(snap.plan == "SuperGrok Plus")
        #expect(snap.windows == [UsageWindow(kind: .weekly, usedPercent: 7,
            resetsAt: Date(timeIntervalSince1970: 1_794_480_227.642))])
        #expect(snap.fetchedAt == Date(timeIntervalSince1970: 7))
        #expect(snap.accountEmail == nil)
        #expect(snap.credits == nil)
        #expect(ch.sent.map { $0["method"] } == [.string("initialize"), .string("_x.ai/billing")])
        try #require(ch.sent.count == 2)
        #expect(ch.sent[0]["params"] == .object([
            "protocolVersion": .number(1), "clientCapabilities": .object([:]),
        ]))
        #expect(ch.sent[1]["params"] == .object([:]))
        #expect(ch.sent.allSatisfy { $0["jsonrpc"] == .string("2.0") })
        #expect(ch.inputFinished)
        #expect(runner.executable?.path == Self.path)
        #expect(runner.arguments == ["agent", "--no-leader", "stdio"])
        #expect(runner.environment.keys.sorted() == ["PATH"])
        let path = try #require(runner.environment["PATH"])
        #expect(path.hasPrefix("/Users/test/.grok/bin:/Users/test/.local/bin:"))
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/usr/local/bin"))
        let entries = path.split(separator: ":").map(String.init)
        #expect(entries.count == Set(entries).count)
        #expect(p.id == .grok)
    }

    @Test func minimumIntervalIsAtLeastFiveMinutes() {
        #expect(provider(ScriptedChannel { _ in [] }).0.minimumInterval >= .seconds(300))
    }

    @Test func cliMissingIsCliNotFound() async {
        let (p, runner) = provider(ScriptedChannel { _ in [] }, found: false)
        await #expect(throws: UsageError.cliNotFound) { try await p.fetch() }
        #expect(runner.runCount == 0)
    }

    @Test(arguments: [-32000, -32601, -32603, -32001, 123], ["initialize", "_x.ai/billing"])
    func serverErrorsUseNumericCode(_ code: Int, method: String) async {
        let ch = ScriptedChannel { msg in
            guard msg["method"] == .string(method) else { return Self.respond(msg) }
            let id = msg["id"]?.intValue ?? 0
            // Auth code has no auth words; other codes do, to catch message-text matching.
            let message = code == -32000 ? "opaque" : "auth login logged in"
            return ["""
            {"jsonrpc":"2.0","id":\(id),"error":{"code":\(code),"message":"\(message)"}}
            """]
        }
        let expected: UsageError
        switch code {
        case -32000: expected = .notLoggedIn
        case -32601: expected = .unexpectedFormat("grok billing method missing")
        case -32603: expected = .network(retryAfter: nil)
        default: expected = .unexpectedFormat("grok error \(code)")
        }
        await #expect(throws: expected) { try await provider(ch).0.fetch() }
    }

    @Test func earlyExitIsUnexpectedFormat() async {
        let ch = ScriptedChannel { _ in [] }
        await #expect(throws: UsageError.unexpectedFormat("grok agent exited early")) {
            try await provider(ch).0.fetch()
        }
    }

    @Test func timeoutIsNetwork() async {
        let ch = ScriptedChannel { _ in [] }
        ch.hangsWhenEmpty = true
        await #expect(throws: UsageError.network(retryAfter: nil)) {
            try await provider(ch, timeout: .milliseconds(100)).0.fetch()
        }
    }

    @Test func cancellationIsNetwork() async {
        let ch = ScriptedChannel { _ in [] }
        ch.hangsWhenEmpty = true
        let (p, _) = provider(ch)
        let task = Task { () -> UsageError? in
            do throws(UsageError) { _ = try await p.fetch(); return nil } catch { return error }
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        #expect(await task.value == .network(retryAfter: nil))
    }

    @Test func writeFailureAfterStartIsUnexpectedFormat() async {
        let ch = ScriptedChannel { _ in [] }
        ch.sendError = POSIXError(.EPIPE)
        await #expect(throws: UsageError.unexpectedFormat("grok agent exited early")) {
            try await provider(ch).0.fetch()
        }
    }

    @Test func launchFailureIsCliNotFound() async {
        let (p, runner) = provider(ScriptedChannel { _ in [] })
        runner.launchError = POSIXError(.ENOENT)
        await #expect(throws: UsageError.cliNotFound) { try await p.fetch() }
        #expect(runner.runCount == 1)
    }

    @Test func mapperErrorPassesThrough() async {
        let ch = ScriptedChannel { msg in
            msg["method"] == .string("initialize") ? Self.respond(msg) : [#"{"jsonrpc":"2.0","id":2,"result":{}}"#]
        }
        await #expect(throws: UsageError.unexpectedFormat("grok config has no creditUsagePercent")) {
            try await provider(ch).0.fetch()
        }
        #expect(ch.inputFinished)
    }

    @Test func versionNoticeAndNonzeroExitStillSucceed() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "agenty-grok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let script = home.appending(path: "billing-stub")
        try """
        #!/bin/sh
        echo 'A new Grok version is available' >&2
        IFS= read -r initialize || exit 10
        printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
        IFS= read -r billing || exit 11
        printf '%s\\n' '\(Self.resultLine)'
        # Wait for the provider to finish input before exiting.
        while IFS= read -r extra; do :; done
        exit 3
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        // Only this temporary shell script is executable to the locator; no real CLI can be selected.
        let locator = CLILocator(home: home, probe: FakeProbe(executables: [script.path]), shell: FakeShell(result: nil))
        let p = GrokProvider(locator: locator, pathOverride: { script.path }, runner: SubprocessRunner(),
                             home: home, timeout: .seconds(5), now: { Date(timeIntervalSince1970: 7) })
        let snap = try await p.fetch()
        #expect(snap.provider == .grok)
        #expect(snap.plan == "SuperGrok Plus")
        #expect(snap.windows == [UsageWindow(kind: .weekly, usedPercent: 7,
            resetsAt: Date(timeIntervalSince1970: 1_794_480_227.642))])
        #expect(snap.fetchedAt == Date(timeIntervalSince1970: 7))
    }
}
