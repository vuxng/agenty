import Foundation
import Synchronization
import Testing
import UsageCore

@Suite struct CodexConfigBackendTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func backend(_ channel: ScriptedChannel, found: Bool = true, codexHome: URL? = nil,
                         timeout: Duration = .seconds(5)) -> (CodexConfigBackend, FakeProcessRunner) {
        let executable = home.appending(path: ".local/bin/codex").path
        let locator = CLILocator(home: home, probe: FakeProbe(executables: found ? [executable] : []),
                                 shell: FakeShell(result: nil))
        let runner = FakeProcessRunner(channel: channel)
        return (CodexConfigBackend(locator: locator, pathOverride: { nil }, runner: runner,
                                   clientVersion: "1.2.3", home: home, codexHome: codexHome, timeout: timeout), runner)
    }

    private func loadChannel(userConfig: JSONValue? = nil, nextCursor: String? = nil) throws -> ScriptedChannel {
        let read = try JSONDecoder().decode(JSONValue.self, from: fixture("codex-config-read"))
        let models = try JSONDecoder().decode(JSONValue.self, from: fixture("codex-model-list"))
        let plugins = try JSONDecoder().decode(JSONValue.self, from: fixture("codex-plugin-installed"))
        return ScriptedChannel { request in
            guard let id = request["id"] else { return [] }
            let result: JSONValue
            switch request["method"] {
            case .string("initialize"): result = .object([:])
            case .string("config/read"):
                if let userConfig {
                    result = .object(["config": .object([:]), "origins": .object([:]), "layers": .array([
                        .object(["name": .object(["type": .string("user")]),
                                 "version": .string("sha256:user"), "config": userConfig]),
                    ])])
                } else { result = read }
            case .string("model/list"):
                if let nextCursor, request["params"]?["cursor"] == nil, case .object(var page) = models {
                    page["nextCursor"] = .string(nextCursor)
                    result = .object(page)
                } else if request["params"]?["cursor"] != nil {
                    result = .object(["data": .array([.object([
                        "model": .string("second-model"), "displayName": .string("Second"),
                        "isDefault": .bool(false), "supportedReasoningEfforts": .array([]),
                        "serviceTiers": .array([]),
                    ])]), "nextCursor": .null])
                } else { result = models }
            case .string("plugin/installed"): result = plugins
            default: return []
            }
            return [String(decoding: try! JSONEncoder().encode(JSONValue.object(["id": id, "result": result])), as: UTF8.self)]
        }
    }

    private func errorChannel(message: String, code: Int = -32600, writeCode: String? = nil) -> ScriptedChannel {
        var error: [String: JSONValue] = ["code": .number(Double(code)), "message": .string(message)]
        if let writeCode { error["data"] = .object(["config_write_error_code": .string(writeCode)]) }
        let response = String(decoding: try! JSONEncoder().encode(JSONValue.object([
            "id": .number(2), "error": .object(error),
        ])), as: UTF8.self)
        return ScriptedChannel(lines: [#"{"id":1,"result":{}}"#, response])
    }

    private func saveChannel(overridden: Bool = false) -> ScriptedChannel {
        ScriptedChannel(lines: [#"{"id":1,"result":{}}"#, overridden
            ? #"{"id":2,"result":{"status":"okOverridden","version":"sha256:new","filePath":"/tmp/config.toml","overriddenMetadata":{"effectiveValue":"system-model","message":"Managed setting wins","overridingLayer":{"name":{"type":"system","file":"/tmp/system.toml"},"version":"sha256:system"}}}}"#
            : #"{"id":2,"result":{"status":"ok","version":"sha256:new","filePath":"/tmp/config.toml","overriddenMetadata":null}}"#])
    }

    @Test func loadReadsUserLayerOnly() async throws {
        let channel = try loadChannel()
        let (backend, runner) = backend(channel)
        let snapshot = try await backend.load()
        #expect(snapshot.version == "sha256:user")
        #expect(snapshot.config.values[["model"]] == .string("gpt-test"))
        #expect(snapshot.config.values[["service_tier"]] == nil)
        #expect(snapshot.config.fast?.lockedValue == nil)
        #expect(backend.provider == .codex)
        #expect(backend.file.url == home.appending(path: ".codex/config.toml"))
        #expect(runner.runCount == 1)
        #expect(runner.arguments == ["app-server"])
        #expect(runner.environment["CODEX_HOME"] == nil)
        #expect(channel.sent.map { $0["method"] } == ["initialize", "initialized", "config/read", "model/list", "plugin/installed"].map(JSONValue.string))
        #expect(channel.sent[2]["params"] == .object(["includeLayers": .bool(true)]))
        #expect(channel.sent[3]["params"] == .object([:]))
        #expect(channel.sent[4]["params"] == .object([:]))
        #expect(channel.inputFinished)
    }

    @Test func loadMapsModelsAndEfforts() async throws {
        let config = try await backend(loadChannel()).0.load().config
        #expect(config.model == ModelSetting(path: ["model"], options: [
            ModelOption(id: "gpt-test", displayName: "Test Model", isDefault: true,
                        efforts: ["low", "high"], fastDescription: "2x speed, increased usage"),
        ], allowsCustom: false))
        #expect(config.efforts == [EffortSetting(path: ["model_reasoning_effort"], modelName: nil, levels: nil)])
        #expect(config.values[["model_reasoning_effort"]] == .string("high"))
        #expect(config.fast == FastSetting(path: ["service_tier"], onValue: .string("priority"),
                                           lockedValue: nil, requiresModelTier: true))
        #expect(config.choices == [
            ConfigChoice(kind: .codexSandbox, path: ["sandbox_mode"],
                         options: [nil, .string("read-only"), .string("workspace-write"), .string("danger-full-access")],
                         dangerous: [.string("danger-full-access")], unsetAliases: []),
            ConfigChoice(kind: .codexApproval, path: ["approval_policy"],
                         options: [nil, .string("untrusted"), .string("on-request"), .string("never")],
                         dangerous: [.string("never")], unsetAliases: []),
        ])
    }

    @Test func modelListFollowsCursor() async throws {
        let channel = try loadChannel(nextCursor: "page-two")
        let config = try await backend(channel).0.load().config
        #expect(config.model.options.map(\.id) == ["gpt-test", "second-model"])
        #expect(config.model.options.last?.efforts == [])
        let calls = channel.sent.filter { $0["method"] == .string("model/list") }
        #expect(calls.map { $0["params"] } == [.object([:]), .object(["cursor": .string("page-two")])])
    }

    @Test func unlistedModelIsAppended() async throws {
        let config = try await backend(loadChannel(userConfig: .object(["model": .string("custom-model")]))).0.load().config
        #expect(config.model.options.last == ModelOption(id: "custom-model", displayName: "custom-model",
                                                         isDefault: false, efforts: nil, fastDescription: nil))
    }

    @Test func loadKeepsOnlyInstalledPlugins() async throws {
        let config = try await backend(loadChannel()).0.load().config
        #expect(config.pluginsComplete)
        #expect(config.plugins == [
            PluginItem(id: "formatter@tools", name: "Formatter", path: ["plugins", "formatter@tools", "enabled"], isEnabled: true),
            PluginItem(id: "x.y@tools", name: "x.y", path: ["plugins", "x.y@tools", "enabled"], isEnabled: false),
        ])
        #expect(config.values[["plugins", "formatter@tools", "enabled"]] == .bool(true))
        #expect(config.values[["plugins", "x.y@tools", "enabled"]] == .bool(false))
        #expect(config.values[["plugins", "uninstalled@tools", "enabled"]] == nil)
    }

    @Test func granularApprovalIsOpaque() async throws {
        let channel = try loadChannel(userConfig: .object(["approval_policy": .object(["granular": .object(["rules": .bool(true)])])]))
        let config = try await backend(channel).0.load().config
        #expect(config.values[["approval_policy"]] == .opaque("granular"))
        #expect(config.choices.last?.options.last == .some(.opaque("granular")))
    }

    @Test(arguments: ["flex", "default", "priority"])
    func flexServiceTierLocksFast(tier: String) async throws {
        let config = try await backend(loadChannel(userConfig: .object(["service_tier": .string(tier)]))).0.load().config
        #expect(config.fast?.lockedValue == (tier == "flex" ? "flex" : nil))
        #expect(config.values[["service_tier"]] == .string(tier))
    }

    @Test func emptyUserLayerKeepsVersion() async throws {
        let snapshot = try await backend(loadChannel(userConfig: .object([:]))).0.load()
        #expect(snapshot.version == "sha256:user")
        #expect(snapshot.config.values[["model"]] == nil)
    }

    @Test func saveSendsBatchWithVersion() async throws {
        let channel = saveChannel()
        let result = try await backend(channel).0.save([
            ConfigEdit(path: ["model"], value: .string("new-model")),
            ConfigEdit(path: ["model_reasoning_effort"], value: nil),
            ConfigEdit(path: ["plugins", "test@tools", "enabled"], value: .bool(false)),
        ], version: "sha256:user")
        #expect(result.overrideMessage == nil)
        #expect(channel.sent[2]["method"] == .string("config/batchWrite"))
        #expect(channel.sent[2]["params"] == .object([
            "expectedVersion": .string("sha256:user"), "edits": .array([
                .object(["keyPath": .string("model"), "value": .string("new-model"), "mergeStrategy": .string("replace")]),
                .object(["keyPath": .string("model_reasoning_effort"), "value": .null, "mergeStrategy": .string("replace")]),
                .object(["keyPath": .string("plugins.test@tools.enabled"), "value": .bool(false), "mergeStrategy": .string("replace")]),
            ]),
        ]))
    }

    @Test func pluginIdWithDotIsQuoted() async throws {
        let channel = saveChannel()
        _ = try await backend(channel).0.save([ConfigEdit(path: ["plugins", "x.y@c", "enabled"], value: .bool(true))], version: nil)
        guard case .array(let edits) = channel.sent[2]["params"]?["edits"] else { Issue.record("Missing edits"); return }
        #expect(edits.first?["keyPath"] == .string("plugins.\"x.y@c\".enabled"))
        #expect(channel.sent[2]["params"]?["expectedVersion"] == .null)
    }

    @Test func versionConflictMapsToConflict() async throws {
        let channel = errorChannel(message: "Configuration was modified since last read. Fetch latest version and retry.", writeCode: "configVersionConflict")
        await #expect(throws: ConfigError.conflict) { try await backend(channel).0.save([], version: "old") }
    }

    @Test func validationErrorMapsToInvalidValue() async throws {
        let message = "Invalid configuration: unknown variant `bogus`, expected one of ...\nin `sandbox_mode`\n"
        let channel = errorChannel(message: message, writeCode: "configValidationError")
        await #expect(throws: ConfigError.invalidValue(message)) { try await backend(channel).0.save([], version: nil) }
    }

    @Test func unknownMethodMapsToUnsupported() async throws {
        let message = "Invalid request: unknown variant `config/nope`, expected one of ..."
        await #expect(throws: ConfigError.unsupportedCLI) { try await backend(errorChannel(message: message)).0.load() }
        await #expect(throws: ConfigError.unsupportedCLI) { try await backend(errorChannel(message: message)).0.save([], version: nil) }
    }

    @Test func overriddenStatusReturnsMessage() async throws {
        let result = try await backend(saveChannel(overridden: true)).0.save([], version: "old")
        #expect(result.overrideMessage == "Managed setting wins")
    }

    @Test func missingCLIThrowsNotFound() async throws {
        await #expect(throws: ConfigError.cliNotFound) { try await backend(ScriptedChannel(lines: []), found: false).0.load() }
    }

    @Test func hangingServerTimesOut() async throws {
        let channel = ScriptedChannel(lines: [])
        channel.hangsWhenEmpty = true
        let backend = backend(channel, timeout: .milliseconds(20)).0
        do { _ = try await backend.load(); Issue.record("Expected timeout") }
        catch { guard case .readFailed = error else { Issue.record(error); return } }
        do { _ = try await backend.save([], version: nil); Issue.record("Expected timeout") }
        catch { guard case .writeFailed = error else { Issue.record(error); return } }
    }

    @Test func serverAndTransportErrorsMapByOperation() async throws {
        let message = "failed to read configuration layers"
        await #expect(throws: ConfigError.invalidFile(message)) { try await backend(errorChannel(message: message, code: -32603)).0.load() }
        await #expect(throws: ConfigError.writeFailed(message)) { try await backend(errorChannel(message: message, code: -32603)).0.save([], version: nil) }
        let backend = backend(ScriptedChannel(lines: [])).0
        do { _ = try await backend.load(); Issue.record("Expected closed") }
        catch { guard case .readFailed = error else { Issue.record(error); return } }
        do { _ = try await backend.save([], version: nil); Issue.record("Expected closed") }
        catch { guard case .writeFailed = error else { Issue.record(error); return } }
    }

    @Test func validateUsesTemporaryHome() async throws {
        let channel = ScriptedChannel(lines: [#"{"id":1,"result":{}}"#])
        channel.hangsWhenEmpty = true
        let (backend, runner) = backend(channel)
        let text = "# keep\nmodel = \"test\"\n"
        let validation = Task { try await backend.validate(text) }
        defer { validation.cancel() }
        for _ in 0..<1000 {
            if channel.sent.contains(where: { $0["method"] == .string("config/read") }) { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        let temporary = URL(filePath: try #require(runner.environment["CODEX_HOME"]))
        #expect(temporary != home)
        #expect(temporary != backend.file.url.deletingLastPathComponent())
        let file = temporary.appending(path: "config.toml")
        #expect(try String(contentsOf: file, encoding: .utf8) == text)
        #expect(try FileManager.default.attributesOfItem(atPath: temporary.path)[.posixPermissions] as? Int == 0o700)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        #expect(channel.sent.last?["params"] == .object([:]))
        validation.cancel()
        _ = await validation.result
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test(arguments: ["original", "canonical", "alias"])
    func validateCleansUpOnFailure(pathStyle: String) async throws {
        let reference = Mutex<FakeProcessRunner?>(nil)
        defer { reference.withLock { $0 = nil } }
        let channel = ScriptedChannel { request in
            if request["method"] == .string("initialize") { return [#"{"id":1,"result":{}}"#] }
            guard request["method"] == .string("config/read") else { return [] }
            let original = reference.withLock { $0?.environment["CODEX_HOME"] } ?? "missing"
            let canonical = URL(filePath: original).resolvingSymlinksInPath().path
            let path = pathStyle == "original" ? original : pathStyle == "canonical" ? canonical
                : canonical.replacingOccurrences(of: "/private/var/", with: "/var/")
                    .replacingOccurrences(of: "/private/tmp/", with: "/tmp/")
            let message = "failed to read configuration layers: \(path)/config.toml:2:9: unclosed table, expected `]`"
            let response: JSONValue = .object(["id": .number(2), "error": .object([
                "code": .number(-32603), "message": .string(message),
            ])])
            return [String(decoding: try! JSONEncoder().encode(response), as: UTF8.self)]
        }
        let (backend, runner) = backend(channel)
        reference.withLock { $0 = runner }
        await #expect(throws: ConfigError.invalidFile("failed to read configuration layers: config.toml:2:9: unclosed table, expected `]`")) {
            try await backend.validate("model = \"test\"\n[broken")
        }
        let path = try #require(runner.environment["CODEX_HOME"])
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func validateWithoutCLIIsUnchecked() async throws {
        #expect(try await backend(ScriptedChannel(lines: []), found: false).0.validate("") == .unchecked)
    }

    @Test func validateOnOldCodexIsUnchecked() async throws {
        let channel = errorChannel(message: "Invalid request: unknown variant `config/read`, expected one of ...")
        let (backend, runner) = backend(channel)
        #expect(try await backend.validate("") == .unchecked)
        #expect(!FileManager.default.fileExists(atPath: try #require(runner.environment["CODEX_HOME"])))
    }

    @Test func validateInvalidEnumThrowsInvalidFile() async throws {
        let message = "invalid configuration: unknown variant `bogus`, expected one of ..."
        let channel = errorChannel(message: message, code: -32603)
        let (backend, runner) = backend(channel)
        await #expect(throws: ConfigError.invalidFile(message)) {
            try await backend.validate("sandbox_mode = \"bogus\"")
        }
        #expect(!FileManager.default.fileExists(atPath: try #require(runner.environment["CODEX_HOME"])))
    }

    @Test func validateSuccessCleansUp() async throws {
        let channel = ScriptedChannel(lines: [#"{"id":1,"result":{}}"#, #"{"id":2,"result":{"config":{},"origins":{}}}"#])
        let (backend, runner) = backend(channel)
        #expect(try await backend.validate("") == .valid)
        #expect(!FileManager.default.fileExists(atPath: try #require(runner.environment["CODEX_HOME"])))
    }

    @Test(.serialized, arguments: ["valid", "invalid", "unsupported"])
    func validateSurfacesCleanupFailure(outcome: String) async throws {
        let reference = Mutex<FakeProcessRunner?>(nil)
        let channel = ScriptedChannel { request in
            if request["method"] == .string("initialize") { return [#"{"id":1,"result":{}}"#] }
            guard request["method"] == .string("config/read") else { return [] }
            do {
                let path = try #require(reference.withLock { $0?.environment["CODEX_HOME"] })
                try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: path)
                if outcome == "valid" { return [#"{"id":2,"result":{"config":{},"origins":{}}}"#] }
                let message = outcome == "invalid"
                    ? "\(path)/config.toml:2:9: unclosed table"
                    : "Invalid request: unknown variant `config/read`, expected one of ..."
                let response: JSONValue = .object(["id": .number(2), "error": .object([
                    "code": .number(outcome == "invalid" ? -32603 : -32600), "message": .string(message),
                ])])
                return [String(decoding: try JSONEncoder().encode(response), as: UTF8.self)]
            } catch { Issue.record(error); return [] }
        }
        let (backend, runner) = backend(channel)
        reference.withLock { $0 = runner }
        defer {
            reference.withLock { $0 = nil }
            do {
                let path = try #require(runner.environment["CODEX_HOME"])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
                try FileManager.default.removeItem(atPath: path)
            } catch { Issue.record(error) }
        }
        do {
            _ = try await backend.validate(outcome == "invalid" ? "[broken" : "")
            Issue.record("Expected cleanup failure")
        } catch {
            guard case .readFailed(let message) = error else { Issue.record(error); return }
            #expect(message.contains("Failed to remove temporary configuration"))
            if outcome == "invalid" {
                #expect(message.contains("config.toml:2:9: unclosed table"))
            }
        }
        let path = try #require(runner.environment["CODEX_HOME"])
        #expect(FileManager.default.fileExists(atPath: path + "/config.toml"))
    }

    @Test func writeFilePreservesTextAndUsesOverride() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let override = home.appending(path: "isolated-codex")
        let (backend, runner) = backend(try loadChannel(), codexHome: override)
        let text = "# exact\r\nmodel = \"custom\"\r\n"
        try await backend.writeFile(text)
        #expect(backend.file.url == override.appending(path: "config.toml"))
        #expect(try backend.file.read() == text)
        _ = try await backend.load()
        #expect(runner.environment["CODEX_HOME"] == override.path)
    }
}
