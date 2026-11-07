import Foundation
import Testing
import UsageCore

@Suite struct ClaudeConfigBackendTests {
    private let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    private func backend(
        found: Bool = false, channel: ScriptedChannel = ScriptedChannel(lines: []),
        timeout: Duration = .seconds(5)
    ) -> (ClaudeConfigBackend, FakeProcessRunner) {
        let executable = home.appending(path: ".local/bin/claude").path
        let locator = CLILocator(home: home, probe: FakeProbe(executables: found ? [executable] : []),
                                 shell: FakeShell(result: nil))
        let runner = FakeProcessRunner(channel: channel)
        return (ClaudeConfigBackend(home: home, locator: locator, runner: runner, timeout: timeout), runner)
    }

    @Test func missingFileLoadsDefaults() async throws {
        let (backend, _) = backend()
        let snapshot = try await backend.load()
        #expect(snapshot.version == nil)
        #expect(snapshot.config.values.isEmpty)
        #expect(backend.provider == .claude)
        #expect(backend.file.url == home.appending(path: ".claude/settings.json"))
        #expect(backend.displayPath == "~/.claude/settings.json")
        #expect(snapshot.config.model.path == ["model"])
        #expect(snapshot.config.model.options.map(\.id) == [
            "best", "fable", "opus", "sonnet", "haiku", "opus[1m]", "sonnet[1m]", "opusplan",
        ])
        #expect(snapshot.config.model.allowsCustom)
        #expect(snapshot.config.model.options.allSatisfy { $0.efforts == nil })
        #expect(snapshot.config.efforts == [
            EffortSetting(path: ["effortLevel"], modelName: nil, levels: ["low", "medium", "high", "xhigh"]),
        ])
        #expect(snapshot.config.fast == FastSetting(path: ["fastMode"], onValue: .bool(true),
                                                   lockedValue: nil, requiresModelTier: false))
        #expect(snapshot.config.choices == [
            ConfigChoice(kind: .claudePermission, path: ["permissions", "defaultMode"],
                         options: [.string("dontAsk"), .string("plan"), nil, .string("acceptEdits"),
                                   .string("auto"), .string("bypassPermissions")],
                         dangerous: [.string("bypassPermissions")],
                         unsetAliases: [.string("default"), .string("manual")]),
            ConfigChoice(kind: .claudeSandbox, path: ["sandbox", "enabled"],
                         options: [nil, .bool(true), .bool(false)], dangerous: [], unsetAliases: []),
        ])
        #expect(!FileManager.default.fileExists(atPath: backend.file.url.path))
    }

    @Test func emptyFileLoadsDefaults() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        try backend.file.write("")
        let snapshot = try await backend.load()
        #expect(snapshot.version == "")
        #expect(snapshot.config.values.isEmpty)
    }

    @Test func nonObjectRootIsInvalid() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        try backend.file.write("[]")
        do {
            _ = try await backend.load()
            Issue.record("Expected invalidFile")
        } catch {
            guard case .invalidFile = error else { Issue.record(error); return }
        }
    }

    @Test func brokenJSONIsInvalid() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        try backend.file.write("{\n  \"model\":\n}")
        do {
            _ = try await backend.load()
            Issue.record("Expected invalidFile")
        } catch {
            guard case .invalidFile(let message) = error else { Issue.record(error); return }
            #expect(message.contains("3"))
        }
    }

    @Test func perModelEffortGetsItsOwnSetting() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        let text = #"{"modelSettings":{"claude-opus-5-5":{"effortLevel":"xhigh"}},"effortLevel":"medium","fastMode":true}"#
        try backend.file.write(text)
        let snapshot = try await backend.load()
        #expect(snapshot.version == text)
        #expect(snapshot.config.efforts == [
            EffortSetting(path: ["modelSettings", "claude-opus-5-5", "effortLevel"],
                          modelName: "claude-opus-5-5", levels: ["low", "medium", "high", "xhigh"]),
            EffortSetting(path: ["effortLevel"], modelName: nil, levels: ["low", "medium", "high", "xhigh"]),
        ])
        #expect(snapshot.config.values == [
            ["modelSettings", "claude-opus-5-5", "effortLevel"]: .string("xhigh"),
            ["effortLevel"]: .string("medium"), ["fastMode"]: .bool(true),
        ])
    }

    @Test func entryWithoutEffortHasNoSlider() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        try backend.file.write(#"{"modelSettings":{"claude-opus-5-5":{"autoCompactWindow":1000}}}"#)
        let config = try await backend.load().config
        #expect(config.efforts.map(\.path) == [["effortLevel"]])
        #expect(config.values.isEmpty)
    }

    @Test func customModelIsAppended() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        try backend.file.write(#"{"model":"claude-opus-5-5"}"#)
        let config = try await backend.load().config
        #expect(config.model.options.count == 9)
        #expect(config.model.options.last?.id == "claude-opus-5-5")
        #expect(config.values[["model"]] == .string("claude-opus-5-5"))
    }

    @Test(arguments: ["delegate", "default", "manual"])
    func unknownModeIsAppended(mode: String) async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        try backend.file.write("{\"permissions\":{\"defaultMode\":\"\(mode)\"}}")
        let config = try await backend.load().config
        let choice = try #require(config.choices.first)
        #expect(choice.options.count == (mode == "delegate" ? 7 : 6))
        #expect(choice.options.contains(.string(mode)) == (mode == "delegate"))
        if mode == "delegate" { #expect(choice.options.last == .some(.string("delegate"))) }
        #expect(config.values[["permissions", "defaultMode"]] == .string(mode))
    }

    @Test func syncedPluginsAreReadOnly() async throws {
        let text = String(decoding: try fixture("claude-plugin-list"), as: UTF8.self)
        let (backend, runner) = backend(found: true, channel: ScriptedChannel(lines: text.components(separatedBy: "\n")))
        let config = try await backend.load().config
        #expect(config.pluginsComplete)
        #expect(config.plugins == [
            PluginItem(id: "formatter@tools", name: "formatter", path: ["enabledPlugins", "formatter@tools"], isEnabled: true),
            PluginItem(id: "reviewer@tools", name: "reviewer", path: nil, isEnabled: false),
        ])
        #expect(config.values == [["enabledPlugins", "formatter@tools"]: .bool(true)])
        #expect(runner.executable == home.appending(path: ".local/bin/claude"))
        #expect(runner.arguments == ["plugin", "list", "--json"])
        let path = try #require(runner.environment["PATH"])
        #expect(path.hasPrefix(home.appending(path: ".local/bin").path + ":"))
        #expect(path.contains("/opt/homebrew/bin"))
    }

    @Test func missingCLIFallsBackToFile() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, runner) = backend()
        try backend.file.write(#"{"enabledPlugins":{"formatter@tools":true,"reviewer@tools":false}}"#)
        let config = try await backend.load().config
        #expect(!config.pluginsComplete)
        #expect(config.plugins == [
            PluginItem(id: "formatter@tools", name: "formatter", path: ["enabledPlugins", "formatter@tools"], isEnabled: true),
            PluginItem(id: "reviewer@tools", name: "reviewer", path: ["enabledPlugins", "reviewer@tools"], isEnabled: false),
        ])
        #expect(config.values == [["enabledPlugins", "formatter@tools"]: .bool(true),
                                  ["enabledPlugins", "reviewer@tools"]: .bool(false)])
        #expect(runner.runCount == 0)
    }

    @Test(arguments: ["malformed", "shape", "launch", "timeout"])
    func pluginFailuresFallBackToFile(failure: String) async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let channel = ScriptedChannel(lines: failure == "shape" ? ["{}"] : ["invalid"])
        channel.hangsWhenEmpty = failure == "timeout"
        let (backend, runner) = backend(found: true, channel: channel, timeout: .milliseconds(20))
        if failure == "launch" { runner.launchError = POSIXError(.ENOENT) }
        try backend.file.write(#"{"enabledPlugins":{"formatter@tools":true}}"#)
        let config = try await backend.load().config
        #expect(!config.pluginsComplete)
        #expect(config.plugins.map(\.id) == ["formatter@tools"])
        #expect(config.values[["enabledPlugins", "formatter@tools"]] == .bool(true))
    }

    @Test func validPluginJSONWithNonzeroExitFallsBackToFile() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let executable = home.appending(path: ".local/bin/claude")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try """
        #!/bin/sh
        echo '[{"id":"cli@tools","scope":"user","enabled":true}]'
        exit 3
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let locator = CLILocator(home: home, probe: FakeProbe(executables: [executable.path]),
                                 shell: FakeShell(result: nil))
        let backend = ClaudeConfigBackend(home: home, locator: locator, runner: SubprocessRunner())
        try backend.file.write(#"{"enabledPlugins":{"file@tools":false}}"#)

        let config = try await backend.load().config

        #expect(!config.pluginsComplete)
        #expect(config.plugins == [
            PluginItem(id: "file@tools", name: "file", path: ["enabledPlugins", "file@tools"], isEnabled: false),
        ])
        #expect(config.values == [["enabledPlugins", "file@tools"]: .bool(false)])
    }

    @Test func unsuccessfulPluginExitFallsBackWithFakeRunner() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let text = String(decoding: try fixture("claude-plugin-list"), as: UTF8.self)
        let (backend, runner) = backend(found: true, channel: ScriptedChannel(lines: [text]))
        runner.exitCode = 3
        try backend.file.write(#"{"enabledPlugins":{"file@tools":false}}"#)

        let config = try await backend.load().config

        #expect(!config.pluginsComplete)
        #expect(config.plugins == [
            PluginItem(id: "file@tools", name: "file", path: ["enabledPlugins", "file@tools"], isEnabled: false),
        ])
        #expect(config.values == [["enabledPlugins", "file@tools"]: .bool(false)])
    }

    @Test func saveChangesOnlyEditedKeys() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        let original = #"{"env":{"KEEP":"yes"},"model":"sonnet","effortLevel":"high","permissions":{"defaultMode":"manual","allow":["Read"]},"tail":1e2}"#
        try backend.file.write(original)
        let result = try await backend.save([ConfigEdit(path: ["model"], value: .string("opus")),
                                             ConfigEdit(path: ["effortLevel"], value: nil)], version: original)
        #expect(result.overrideMessage == nil)
        #expect(try backend.file.read() == """
        {
          "env": {
            "KEEP": "yes"
          },
          "model": "opus",
          "permissions": {
            "defaultMode": "manual",
            "allow": [
              "Read"
            ]
          },
          "tail": 1e2
        }

        """)
    }

    @Test func saveDetectsConflict() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        let current = #"{"model":"haiku"}"#
        try backend.file.write(current)
        await #expect(throws: ConfigError.conflict) {
            try await backend.save([ConfigEdit(path: ["model"], value: .string("opus"))], version: "{}")
        }
        await #expect(throws: ConfigError.conflict) { try await backend.save([], version: nil) }
        #expect(try backend.file.read() == current)
    }

    @Test func saveCreatesMissingFile() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        _ = try await backend.save([ConfigEdit(path: ["model"], value: .string("opus")),
                                    ConfigEdit(path: ["sandbox", "enabled"], value: .bool(false))], version: nil)
        #expect(try backend.file.read() == "{\n  \"model\": \"opus\",\n  \"sandbox\": {\n    \"enabled\": false\n  }\n}\n")
    }

    @Test func validateRejectsBrokenJSON() async throws {
        let (backend, _) = backend()
        for text in ["", " \t\r\n", "{", "[]", "null", "false", "1", "\"model\""] {
            do {
                _ = try await backend.validate(text)
                Issue.record("Expected invalidFile for \(text)")
            } catch {
                guard case .invalidFile = error else { Issue.record(error); continue }
            }
        }
        for text in ["{}", "{\"model\":\"opus\"}"] {
            #expect(try await backend.validate(text) == .valid)
        }
        #expect(!FileManager.default.fileExists(atPath: backend.file.url.path))
    }

    @Test func opaqueChoicesArePreservedByOtherEdits() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        let original = #"{"permissions":{"defaultMode":{"granular":[true]}},"sandbox":{"enabled":"future"}}"#
        try backend.file.write(original)
        let config = try await backend.load().config
        let opaque = try #require(config.values[["permissions", "defaultMode"]])
        guard case .opaque(let text) = opaque else { Issue.record("Expected opaque value"); return }
        #expect(try OrderedJSON(parsing: text).value(at: ["granular"]) == .array([.bool(true)]))
        #expect(config.choices[0].options.last == .some(opaque))
        #expect(config.choices[1].options.last == .some(.string("future")))
        _ = try await backend.save([ConfigEdit(path: ["model"], value: .string("opus"))], version: original)
        let saved = try OrderedJSON(parsing: #require(try backend.file.read()))
        #expect(try saved.value(at: ["permissions", "defaultMode"]) == OrderedJSON(parsing: text))
    }

    @Test func writeFilePreservesTextExactly() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        let text = "{ \"model\": \"opus\" }\r\n"
        try await backend.writeFile(text)
        #expect(try backend.file.read() == text)
    }

    @Test func fileErrorsAreMapped() async throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let (backend, _) = backend()
        try backend.file.write("")
        try Data([0xFF]).write(to: backend.file.url)
        do {
            _ = try await backend.load()
            Issue.record("Expected readFailed")
        } catch {
            guard case .readFailed = error else { Issue.record(error); return }
        }
        try FileManager.default.removeItem(at: backend.file.url.deletingLastPathComponent())
        try Data().write(to: backend.file.url.deletingLastPathComponent())
        do {
            try await backend.writeFile("{}")
            Issue.record("Expected writeFailed")
        } catch {
            guard case .writeFailed = error else { Issue.record(error); return }
        }
    }
}
