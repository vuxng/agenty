import Foundation

public struct ClaudeConfigBackend: ConfigBackend {
    public let provider: ProviderID = .claude
    public let file: TextFile
    private let home: URL
    private let locator: CLILocator
    private let runner: any ProcessRunner
    private let timeout: Duration

    public init(home: URL, locator: CLILocator, runner: any ProcessRunner, timeout: Duration = .seconds(15)) {
        self.home = home
        self.file = TextFile(url: home.appending(path: ".claude/settings.json"))
        self.locator = locator
        self.runner = runner
        self.timeout = timeout
    }

    public func load() async throws(ConfigError) -> ConfigSnapshot {
        let version = try readFile()
        let root = try Self.parse(version ?? "")
        let levels = ["low", "medium", "high", "xhigh"]
        var modelNames = ["best", "fable", "opus", "sonnet", "haiku", "opus[1m]", "sonnet[1m]", "opusplan"]
        if case .string(let model) = root.value(at: ["model"]), !modelNames.contains(model) {
            modelNames.append(model)
        }
        let model = ModelSetting(path: ["model"], options: modelNames.map {
            ModelOption(id: $0, displayName: $0, isDefault: $0 == "best", efforts: levels, fastDescription: nil)
        }, allowsCustom: true)
        var efforts: [EffortSetting] = []
        if case .object(let members) = root.value(at: ["modelSettings"]) {
            for member in members where member.value.value(at: ["effortLevel"]) != nil {
                efforts.append(EffortSetting(path: ["modelSettings", member.key, "effortLevel"],
                                             modelName: member.key, levels: levels))
            }
        }
        efforts.append(EffortSetting(path: ["effortLevel"], modelName: nil, levels: levels))
        let fast = FastSetting(path: ["fastMode"], onValue: .bool(true), lockedValue: nil, requiresModelTier: false)
        let choices = [
            Self.choice(root: root, kind: .claudePermission, path: ["permissions", "defaultMode"],
                        options: [.string("dontAsk"), .string("plan"), nil, .string("acceptEdits"),
                                  .string("auto"), .string("bypassPermissions")],
                        dangerous: [.string("bypassPermissions")],
                        unsetAliases: [.string("default"), .string("manual")]),
            Self.choice(root: root, kind: .claudeSandbox, path: ["sandbox", "enabled"],
                        options: [nil, .bool(true), .bool(false)], dangerous: [], unsetAliases: []),
        ]
        let listedPlugins = await listPlugins()
        let plugins = listedPlugins ?? Self.filePlugins(root)
        var values: [ConfigPath: ConfigValue] = [:]
        for path in [model.path, fast.path] + efforts.map(\.path) + choices.map(\.path) {
            if let value = root.value(at: path) { values[path] = Self.configValue(value) }
        }
        for plugin in plugins {
            if let path = plugin.path { values[path] = .bool(plugin.isEnabled) }
        }
        return ConfigSnapshot(config: AgentConfig(model: model, efforts: efforts, fast: fast, choices: choices,
                                                  plugins: plugins, pluginsComplete: listedPlugins != nil,
                                                  values: values), version: version)
    }

    public func save(_ edits: [ConfigEdit], version: String?) async throws(ConfigError) -> ConfigSaveResult {
        let current = try readFile()
        switch (current, version) {
        case (nil, nil): break
        case (.some(let current), .some(let version)) where current.utf8.elementsEqual(version.utf8): break
        default: throw .conflict
        }
        var root = try Self.parse(current ?? "")
        for edit in edits {
            switch edit.value {
            case .bool(let value): root.set(.bool(value), at: edit.path)
            case .string(let value): root.set(.string(value), at: edit.path)
            case .opaque: throw .invalidValue("Cannot edit an opaque JSON value")
            case nil: root.remove(at: edit.path)
            }
        }
        try write(root.serialized())
        return ConfigSaveResult(overrideMessage: nil)
    }

    public func validate(_ text: String) async throws(ConfigError) -> ConfigValidation {
        _ = try Self.parse(text)
        return .valid
    }

    public func writeFile(_ text: String) async throws(ConfigError) {
        try write(text)
    }

    private func readFile() throws(ConfigError) -> String? {
        do { return try file.read() }
        catch { throw .readFailed(String(describing: error)) }
    }

    private func write(_ text: String) throws(ConfigError) {
        do { try file.write(text) }
        catch { throw .writeFailed(String(describing: error)) }
    }

    private static func parse(_ text: String) throws(ConfigError) -> OrderedJSON {
        if text.isEmpty { return .object([]) }
        let root: OrderedJSON
        do { root = try OrderedJSON(parsing: text) }
        catch { throw .invalidFile(String(describing: error)) }
        guard case .object = root else { throw .invalidFile("Expected a JSON object") }
        return root
    }

    private static func configValue(_ value: OrderedJSON) -> ConfigValue {
        switch value {
        case .bool(let value): return .bool(value)
        case .string(let value): return .string(value)
        default: return .opaque(String(value.serialized().dropLast()))
        }
    }

    private static func choice(root: OrderedJSON, kind: ConfigChoiceKind, path: ConfigPath,
                               options: [ConfigValue?], dangerous: Set<ConfigValue>,
                               unsetAliases: Set<ConfigValue>) -> ConfigChoice {
        var options = options
        if let value = root.value(at: path).map(configValue),
           !options.contains(value), !unsetAliases.contains(value) {
            options.append(value)
        }
        return ConfigChoice(kind: kind, path: path, options: options, dangerous: dangerous, unsetAliases: unsetAliases)
    }

    private func listPlugins() async -> [PluginItem]? {
        guard let executable = await locator.locate("claude", override: nil) else { return nil }
        do {
            return try await withTimeout(timeout) {
                try await runner.run(executable: executable, arguments: ["plugin", "list", "--json"],
                                     environment: ["PATH": CodexProvider.searchPath(executable: executable, home: home)],
                                     requireSuccessfulExit: true) { channel in
                    try await channel.finishInput()
                    var lines: [String] = []
                    while let line = try await channel.receive() { lines.append(line) }
                    let records = try JSONDecoder().decode([ListedPlugin].self, from: Data(lines.joined(separator: "\n").utf8))
                    return records.map {
                        PluginItem(id: $0.id, name: Self.pluginName($0.id),
                                   path: $0.scope == "user" ? ["enabledPlugins", $0.id] : nil, isEnabled: $0.enabled)
                    }
                }
            }
        } catch {
            return nil
        }
    }

    private static func filePlugins(_ root: OrderedJSON) -> [PluginItem] {
        guard case .object(let members) = root.value(at: ["enabledPlugins"]) else { return [] }
        return members.compactMap {
            guard case .bool(let enabled) = $0.value else { return nil }
            return PluginItem(id: $0.key, name: pluginName($0.key), path: ["enabledPlugins", $0.key], isEnabled: enabled)
        }
    }

    private static func pluginName(_ id: String) -> String {
        String(id.prefix { $0 != "@" })
    }

    private struct ListedPlugin: Decodable {
        let id: String
        let scope: String
        let enabled: Bool
    }
}
