import Foundation
import Synchronization
import Testing
@testable import UsageCore

@Suite struct CodexAgentSourceTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func source(_ channel: ScriptedChannel, found: Bool = true) -> (CodexAgentSource, FakeProcessRunner) {
        let executable = home.appending(path: ".local/bin/codex").path
        let locator = CLILocator(home: home, probe: FakeProbe(executables: found ? [executable] : []),
                                 shell: FakeShell(result: nil))
        let runner = FakeProcessRunner(channel: channel)
        return (CodexAgentSource(locator: locator, pathOverride: { nil }, runner: runner,
                                 clientVersion: "1.2.3", home: home, timeout: .seconds(5)), runner)
    }

    @discardableResult
    private func write(_ path: String, _ text: String = "name = \"test\"\n") throws -> URL {
        let url = home.appending(path: ".codex/agents/" + path)
        try TextFile(url: url).write(text)
        return url
    }

    private func channel(configs: [String]) -> ScriptedChannel {
        let index = Mutex(0)
        return ScriptedChannel { request in
            guard let id = request["id"]?.intValue else { return [] }
            if request["method"] == .string("initialize") { return [#"{"id":\#(id),"result":{}}"#] }
            guard request["method"] == .string("config/read") else { return [] }
            #expect(request["params"] == .object(["includeLayers": .bool(true)]))
            let next = index.withLock { value in defer { value += 1 }; return value }
            guard configs.indices.contains(next) else { Issue.record("Unexpected config/read"); return [] }
            return [#"{"id":\#(id),"result":{"config":{"name":"merged"},"origins":{},"layers":[{"name":{"type":"system"},"config":{"name":"system"}},{"name":{"type":"user"},"version":"sha256:user","config":\#(configs[next])}]}}"#]
        }
    }

    @Test func mapsUserLayerConfigInOrder() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let url = try write("reviewer.toml")
        let channel = channel(configs: [##"{"name":"reviewer","description":"Reviews","developer_instructions":"# Hi\n- one\n","model":"gpt-5.5","nickname_candidates":["Rev","R2"],"features":{"apps":false},"model_verbosity":"low"}"##])
        let (source, runner) = source(channel)
        let listing = try await source.load()
        let agent = try #require(listing.agents.first)
        #expect(agent.url == url)
        #expect(agent.name == "reviewer")
        #expect(agent.description == "Reviews")
        #expect(agent.model == "gpt-5.5")
        #expect(agent.prompt == "# Hi\n- one")
        #expect(agent.fields == [
            AgentField(key: "nickname_candidates", value: .text("Rev, R2")),
            AgentField(key: "features", value: .block("{\n  \"apps\": false\n}")),
            AgentField(key: "model_verbosity", value: .text("low")),
        ])
        #expect(agent.readError == nil)
        #expect(!agent.isLineScanned)
        #expect(listing.folderExists)
        #expect(!listing.usesClaudeAgents)
        #expect(source.provider == .codex)
        #expect(source.directory.url.path == home.appending(path: ".codex/agents").path)
        #expect(source.directory.fileExtension == "toml")
        #expect(source.directory.recursive)
        #expect(runner.runCount == 1)
        #expect(runner.arguments == ["app-server"])
        #expect(channel.inputFinished)
    }

    @Test func oneBadFileDoesNotStopTheOthers() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let bad = try write("bad.toml", "name = \"bad\"\ndescription = \"unterminated\n")
        let good = try write("good.toml", "name = \"good\"\n")
        let reference = Mutex<FakeProcessRunner?>(nil)
        defer { reference.withLock { $0 = nil } }
        let channel = ScriptedChannel { request in
            guard let id = request["id"]?.intValue else { return [] }
            if request["method"] == .string("initialize") { return [#"{"id":1,"result":{}}"#] }
            guard request["method"] == .string("config/read") else { return [] }
            if id == 2 {
                let path = reference.withLock { $0?.environment["CODEX_HOME"] } ?? "missing"
                let resolved = URL(filePath: path).resolvingSymlinksInPath().path
                let message = "failed to read configuration layers: \(path)/config.toml:2:28: invalid basic string; \(resolved)/config.toml:2:28; \(path)/other; \(resolved)/other"
                let encoded = String(decoding: try! JSONEncoder().encode(message), as: UTF8.self)
                return [#"{"id":2,"error":{"code":-32603,"message":\#(encoded)}}"#]
            }
            return [#"{"id":\#(id),"result":{"layers":[{"name":{"type":"user"},"config":{"name":"good"}}]}}"#]
        }
        let (source, runner) = source(channel)
        reference.withLock { $0 = runner }
        let listing = try await source.load()
        #expect(listing.agents.map(\.url) == [bad, good])
        guard case .failed(let message) = listing.agents.first?.readError else {
            Issue.record("Expected failed read"); return
        }
        #expect(message.contains("bad.toml:2:28"))
        let path = try #require(runner.environment["CODEX_HOME"])
        #expect(!message.contains(path))
        #expect(!message.contains(URL(filePath: path).resolvingSymlinksInPath().path))
        #expect(!message.contains("config.toml"))
        #expect(listing.agents.last?.name == "good")
        #expect(listing.agents.last?.readError == nil)
        #expect(runner.runCount == 1)
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func skipsFilesWithoutName() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        for name in ["absent", "empty", "whitespace", "wrong-type"] { try write(name + ".toml") }
        let listing = try await source(channel(configs: [#"{}"#, #"{"name":""}"#,
            #"{"name":" \n\t "}"#, #"{"name":42}"#])).0.load()
        #expect(listing.folderExists)
        #expect(listing.agents.isEmpty)
    }

    @Test func skipsMissingUserLayer() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("system.toml")
        let channel = ScriptedChannel { request in
            guard let id = request["id"]?.intValue else { return [] }
            return [#"{"id":\#(id),"result":{"config":{"name":"merged"},"layers":[{"name":{"type":"system"},"config":{"name":"system"}}]}}"#]
        }
        #expect(try await source(channel).0.load().agents.isEmpty)
    }

    @Test func readsSubfolders() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let top = try write("a.toml")
        let nested = try write("sub/x.toml")
        try write("ignored.txt")
        try write(".hidden.toml")
        let listing = try await source(channel(configs: [#"{"name":"zeta"}"#, #"{"name":"alpha"}"#])).0.load()
        #expect(listing.agents.map(\.url) == [nested, top])
        #expect(listing.agents.map(\.name) == ["alpha", "zeta"])
    }

    @Test func missingOrEmptyFolderDoesNotLaunchCodex() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (source, runner) = source(ScriptedChannel(lines: []))
        let missing = try await source.load()
        #expect(!missing.folderExists)
        #expect(missing.agents.isEmpty)
        try FileManager.default.createDirectory(at: source.directory.url, withIntermediateDirectories: true)
        let empty = try await source.load()
        #expect(empty.folderExists)
        #expect(empty.agents.isEmpty)
        #expect(runner.runCount == 0)
    }

    @Test func missingCLIThrows() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("a.toml")
        let (source, runner) = source(ScriptedChannel(lines: []), found: false)
        await #expect(throws: AgentLoadError.cliNotFound) { try await source.load() }
        #expect(runner.runCount == 0)
    }

    @Test func launchFailureThrowsFailed() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("a.toml")
        let (source, runner) = source(ScriptedChannel(lines: []))
        runner.launchError = JSONRPCError.closed
        await #expect(throws: AgentLoadError.failed("closed")) { try await source.load() }
    }

    @Test(arguments: [false, true])
    func removesTemporaryHome(launchFails: Bool) async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("a.toml")
        let (source, runner) = source(channel(configs: [#"{"name":"a"}"#]))
        if launchFails { runner.launchError = JSONRPCError.closed }
        do { _ = try await source.load(); #expect(!launchFails) }
        catch { #expect(launchFails) }
        let path = try #require(runner.environment["CODEX_HOME"])
        #expect(URL(filePath: path).lastPathComponent.hasPrefix("agenty-agents-"))
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func mapsRemainingValueTypesAndPreservesNumberLiterals() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("a.toml")
        let listing = try await source(channel(configs: [#"{"name":"  a  ","model":"inherit","developer_instructions":" \n ","multiline":"one\ntwo\n","number":1.20e+3,"enabled":true,"simple":["one",2,false],"nested":[{"x":true}],"absent":null}"#])).0.load()
        let agent = try #require(listing.agents.first)
        #expect(agent.name == "a")
        #expect(agent.model == nil)
        #expect(agent.prompt == nil)
        #expect(agent.fields.first { $0.key == "multiline" }?.value == .block("one\ntwo\n"))
        #expect(agent.fields.first { $0.key == "number" }?.value == .text("1.20e+3"))
        #expect(agent.fields.first { $0.key == "enabled" }?.value == .text("true"))
        #expect(agent.fields.first { $0.key == "simple" }?.value == .text("one, 2, false"))
        #expect(agent.fields.first { $0.key == "nested" }?.value == .block("[\n  {\n    \"x\": true\n  }\n]"))
        #expect(!agent.fields.contains { $0.key == "absent" })
    }

    @Test func nonTextFileDoesNotStopTheOthers() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let bad = try write("bad.toml")
        try Data([0xFF, 0xFE]).write(to: bad)
        try write("good.toml")
        let listing = try await source(channel(configs: [#"{"name":"good"}"#])).0.load()
        #expect(listing.agents.map(\.name) == ["bad", "good"])
        #expect(listing.agents.first?.readError == .notText)
        #expect(listing.agents.last?.readError == nil)
    }

    @Test func unreadableDirectoryFailsBeforeLaunch() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("a.toml")
        let (source, runner) = source(ScriptedChannel(lines: []))
        let folder = source.directory.url
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        do { _ = try await source.load(); Issue.record("Expected directory failure") }
        catch { guard case .failed = error else { Issue.record(error); return } }
        #expect(runner.runCount == 0)
    }

    @Test func sessionFailureEndsLoadAndCleansUp() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("a.toml")
        try write("b.toml")
        let channel = ScriptedChannel(lines: [#"{"id":1,"result":{}}"#])
        let (source, runner) = source(channel)
        await #expect(throws: AgentLoadError.failed("closed")) { try await source.load() }
        #expect(channel.sent.filter { $0["method"] == .string("config/read") }.count == 1)
        #expect(!FileManager.default.fileExists(atPath: try #require(runner.environment["CODEX_HOME"])))
    }

    @Test func startsEmptyAndOverwritesPrivateConfigForEachFile() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let first = "name = \"first-long-name\"\n"
        let second = "name = \"b\"\n"
        let a = try write("a.toml", first)
        let b = try write("b.toml", second)
        let reference = Mutex<FakeProcessRunner?>(nil)
        defer { reference.withLock { $0 = nil } }
        let channel = ScriptedChannel { request in
            guard let id = request["id"]?.intValue else { return [] }
            do {
                let path = try #require(reference.withLock { $0?.environment["CODEX_HOME"] })
                #expect(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int == 0o700)
                if request["method"] == .string("initialize") {
                    #expect(try FileManager.default.contentsOfDirectory(atPath: path).isEmpty)
                    return [#"{"id":1,"result":{}}"#]
                }
                let file = URL(filePath: path).appending(path: "config.toml")
                #expect(try String(contentsOf: file, encoding: .utf8) == (id == 2 ? first : second))
                #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
            } catch { Issue.record(error) }
            return [#"{"id":\#(id),"result":{"layers":[{"name":{"type":"user"},"config":{"name":"same"}}]}}"#]
        }
        let (source, runner) = source(channel)
        reference.withLock { $0 = runner }
        let listing = try await source.load()
        #expect(listing.agents.map(\.url) == [a, b])
        #expect(try TextFile(url: a).read() == first)
        #expect(try TextFile(url: b).read() == second)
        #expect(runner.runCount == 1)
    }

    @Test func cancellationRemovesTemporaryHome() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        try write("a.toml")
        let channel = ScriptedChannel(lines: [#"{"id":1,"result":{}}"#])
        channel.hangsWhenEmpty = true
        let (source, runner) = source(channel)
        let load = Task { try await source.load() }
        defer { load.cancel() }
        for _ in 0..<1000 {
            if channel.sent.contains(where: { $0["method"] == .string("config/read") }) { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(channel.sent.contains { $0["method"] == .string("config/read") })
        let path = try #require(runner.environment["CODEX_HOME"])
        load.cancel()
        switch await load.result {
        case .success: Issue.record("Expected cancellation to fail load")
        case .failure(let error):
            guard case AgentLoadError.failed = error else { Issue.record(error); return }
        }
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
