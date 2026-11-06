import Foundation

public struct CodexConfigBackend: ConfigBackend {
    public let provider: ProviderID = .codex
    public let file: TextFile
    private let server: CodexAppServer
    private let environment: [String: String]

    public init(locator: CLILocator, pathOverride: @escaping @Sendable () -> String?, runner: any ProcessRunner,
                clientVersion: String, home: URL, codexHome: URL? = nil, timeout: Duration = .seconds(15)) {
        self.file = TextFile(url: (codexHome ?? home.appending(path: ".codex")).appending(path: "config.toml"))
        self.server = CodexAppServer(locator: locator, pathOverride: pathOverride, runner: runner,
                                    clientVersion: clientVersion, home: home, timeout: timeout)
        self.environment = codexHome.map { ["CODEX_HOME": $0.path] } ?? [:]
    }

    public func load() async throws(ConfigError) -> ConfigSnapshot {
        do {
            return try await server.withSession(environment: environment) { rpc in
                let response = try JSONDecoder().decode(ReadResponse.self, from: await rpc.call(
                    "config/read", params: .object(["includeLayers": .bool(true)])))
                guard let user = response.layers.first(where: { $0.name.type == "user" }) else {
                    throw ResponseError.missingUserLayer
                }
                var models: [ModelOption] = []
                var cursor: String?
                repeat {
                    let params: JSONValue = .object(cursor.map { ["cursor": .string($0)] } ?? [:])
                    let page = try JSONDecoder().decode(ModelPage.self, from: await rpc.call("model/list", params: params))
                    models += page.data.map {
                        ModelOption(id: $0.model, displayName: $0.displayName, isDefault: $0.isDefault,
                                    efforts: $0.supportedReasoningEfforts.map(\.reasoningEffort),
                                    fastDescription: $0.serviceTiers?.first?.description)
                    }
                    cursor = page.nextCursor
                } while cursor != nil
                let plugins = try JSONDecoder().decode(PluginResponse.self, from: await rpc.call(
                    "plugin/installed", params: .object([:])))
                return Self.snapshot(user: user, models: models, plugins: plugins)
            }
        } catch { throw Self.mapError(error, saving: false) }
    }

    public func save(_ edits: [ConfigEdit], version: String?) async throws(ConfigError) -> ConfigSaveResult {
        do {
            let edits: [JSONValue] = try edits.map { edit in
                let value: JSONValue
                switch edit.value {
                case .bool(let flag): value = .bool(flag)
                case .string(let text): value = .string(text)
                case nil: value = .null
                case .opaque: throw ConfigError.invalidValue("Cannot edit an opaque config value")
                }
                return .object([
                    "keyPath": .string(edit.path.map(Self.keyComponent).joined(separator: ".")),
                    "value": value, "mergeStrategy": .string("replace"),
                ])
            }
            return try await server.withSession(environment: environment) { rpc in
                let response = try JSONDecoder().decode(WriteResponse.self, from: await rpc.call(
                    "config/batchWrite", params: .object([
                        "edits": .array(edits), "expectedVersion": version.map(JSONValue.string) ?? .null,
                    ])))
                return ConfigSaveResult(overrideMessage: response.status == .okOverridden
                                        ? response.overriddenMetadata?.message : nil)
            }
        } catch { throw Self.mapError(error, saving: true) }
    }

    public func validate(_ text: String) async throws(ConfigError) -> ConfigValidation {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? manager.removeItem(at: temporary) }
        do {
            try manager.createDirectory(at: temporary, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            let temporaryFile = temporary.appending(path: "config.toml")
            try Data(text.utf8).write(to: temporaryFile, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryFile.path)
            return try await server.withSession(environment: ["CODEX_HOME": temporary.path]) { rpc in
                _ = try await rpc.call("config/read", params: .object([:]))
                return .valid
            }
        } catch {
            let mapped = Self.mapError(error, saving: false, temporary: temporary)
            switch mapped {
            case .cliNotFound, .unsupportedCLI: return .unchecked
            default: throw mapped
            }
        }
    }

    public func writeFile(_ text: String) async throws(ConfigError) {
        do { try file.write(text) }
        catch { throw .writeFailed(String(describing: error)) }
    }

    private static func snapshot(user: UserLayer, models: [ModelOption], plugins response: PluginResponse) -> ConfigSnapshot {
        let root = user.config
        var models = models
        if case .string(let name)? = root["model"], !models.contains(where: { $0.id == name }) {
            models.append(ModelOption(id: name, displayName: name, isDefault: false, efforts: [], fastDescription: nil))
        }
        let model = ModelSetting(path: ["model"], options: models, allowsCustom: false)
        let efforts = [EffortSetting(path: ["model_reasoning_effort"], modelName: nil, levels: nil)]
        var lockedTier: String?
        if case .string(let tier)? = root["service_tier"], tier != "priority", tier != "default" { lockedTier = tier }
        let fast = FastSetting(path: ["service_tier"], onValue: .string("priority"),
                               lockedValue: lockedTier, requiresModelTier: true)
        var values: [ConfigPath: ConfigValue] = [:]
        for key in ["model", "model_reasoning_effort", "service_tier", "sandbox_mode", "approval_policy"] {
            if let value = root[key], value != .null {
                if key == "approval_policy", case .object = value { values[[key]] = .opaque("granular") }
                else { values[[key]] = configValue(value) }
            }
        }
        let choices = [
            choice(kind: .codexSandbox, key: "sandbox_mode",
                   options: [nil, .string("read-only"), .string("workspace-write"), .string("danger-full-access")],
                   dangerous: [.string("danger-full-access")], values: values),
            choice(kind: .codexApproval, key: "approval_policy",
                   options: [nil, .string("untrusted"), .string("on-request"), .string("never")],
                   dangerous: [.string("never")], values: values),
        ]
        let plugins = response.marketplaces.flatMap(\.plugins).filter(\.installed).map {
            PluginItem(id: $0.id, name: $0.interface?.displayName ?? String($0.id.prefix { $0 != "@" }),
                       path: ["plugins", $0.id, "enabled"], isEnabled: $0.enabled)
        }
        for plugin in plugins {
            if let path = plugin.path { values[path] = .bool(plugin.isEnabled) }
        }
        return ConfigSnapshot(config: AgentConfig(model: model, efforts: efforts, fast: fast, choices: choices,
                                                  plugins: plugins,
                                                  pluginsComplete: response.marketplaceLoadErrors?.isEmpty != false,
                                                  values: values), version: user.version)
    }

    private static func choice(kind: ConfigChoiceKind, key: String, options: [ConfigValue?],
                               dangerous: Set<ConfigValue>, values: [ConfigPath: ConfigValue]) -> ConfigChoice {
        var options = options
        if let value = values[[key]], !options.contains(value) { options.append(value) }
        return ConfigChoice(kind: kind, path: [key], options: options, dangerous: dangerous, unsetAliases: [])
    }

    private static func configValue(_ value: JSONValue) -> ConfigValue {
        switch value {
        case .bool(let value): return .bool(value)
        case .string(let value): return .string(value)
        default:
            let data = try? JSONEncoder().encode(value)
            return .opaque(data.map { String(decoding: $0, as: UTF8.self) } ?? "null")
        }
    }

    private static func keyComponent(_ component: String) -> String {
        guard component.contains(".") else { return component }
        return "\"" + component.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func mapError(_ error: any Error, saving: Bool, temporary: URL? = nil) -> ConfigError {
        if let error = error as? ConfigError { return error }
        if case CodexAppServerError.cliNotFound = error { return .cliNotFound }
        func sanitized(_ message: String) -> String {
            guard let temporary else { return message }
            return message.replacingOccurrences(of: temporary.path + "/", with: "")
                .replacingOccurrences(of: temporary.resolvingSymlinksInPath().path + "/", with: "")
        }
        if case JSONRPCError.server(_, let message, let data) = error {
            let message = sanitized(message)
            let writeCode = data?["config_write_error_code"]
            if writeCode == .string("configVersionConflict") { return .conflict }
            if writeCode == .string("configValidationError") { return .invalidValue(message) }
            if (writeCode == nil || writeCode == .null), message.contains("unknown variant") { return .unsupportedCLI }
            return saving ? .writeFailed(message) : .invalidFile(message)
        }
        let message = sanitized(String(describing: error))
        return saving ? .writeFailed(message) : .readFailed(message)
    }

    private enum ResponseError: Error { case missingUserLayer }

    private struct ReadResponse: Decodable {
        let layers: [UserLayer]
    }

    private struct UserLayer: Decodable {
        struct Name: Decodable { let type: String }
        let name: Name
        let version: String
        let config: JSONValue
    }

    private struct ModelPage: Decodable {
        struct Model: Decodable {
            struct Effort: Decodable { let reasoningEffort: String }
            struct Tier: Decodable { let description: String }
            let model: String
            let displayName: String
            let isDefault: Bool
            let supportedReasoningEfforts: [Effort]
            let serviceTiers: [Tier]?
        }
        let data: [Model]
        let nextCursor: String?
    }

    private struct PluginResponse: Decodable {
        struct Marketplace: Decodable {
            struct Plugin: Decodable {
                struct Interface: Decodable { let displayName: String? }
                let id: String
                let installed: Bool
                let enabled: Bool
                let interface: Interface?
            }
            let plugins: [Plugin]
        }
        let marketplaces: [Marketplace]
        let marketplaceLoadErrors: [JSONValue]?
    }

    private struct WriteResponse: Decodable {
        enum Status: String, Decodable { case ok, okOverridden }
        struct Metadata: Decodable { let message: String }
        let status: Status
        let overriddenMetadata: Metadata?
    }
}
