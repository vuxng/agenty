public typealias ConfigPath = [String]

public enum ConfigValue: Sendable, Hashable {
    case bool(Bool), string(String), opaque(String)
}

public struct ConfigEdit: Sendable, Equatable {
    public let path: ConfigPath
    public let value: ConfigValue?

    public init(path: ConfigPath, value: ConfigValue?) {
        self.path = path
        self.value = value
    }
}

public enum ConfigChoiceKind: Sendable {
    case claudePermission, claudeSandbox, codexSandbox, codexApproval
}

public struct ConfigChoice: Sendable, Equatable {
    public let kind: ConfigChoiceKind
    public let path: ConfigPath
    public let options: [ConfigValue?]
    public let dangerous: Set<ConfigValue>
    public let unsetAliases: Set<ConfigValue>

    public init(kind: ConfigChoiceKind, path: ConfigPath, options: [ConfigValue?],
                dangerous: Set<ConfigValue>, unsetAliases: Set<ConfigValue>) {
        self.kind = kind
        self.path = path
        self.options = options
        self.dangerous = dangerous
        self.unsetAliases = unsetAliases
    }
}

public struct ModelOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let isDefault: Bool
    public let efforts: [String]
    public let fastDescription: String?

    public init(id: String, displayName: String, isDefault: Bool, efforts: [String], fastDescription: String?) {
        self.id = id
        self.displayName = displayName
        self.isDefault = isDefault
        self.efforts = efforts
        self.fastDescription = fastDescription
    }
}

public struct ModelSetting: Sendable, Equatable {
    public let path: ConfigPath
    public let options: [ModelOption]
    public let allowsCustom: Bool

    public init(path: ConfigPath, options: [ModelOption], allowsCustom: Bool) {
        self.path = path
        self.options = options
        self.allowsCustom = allowsCustom
    }
}

public struct EffortSetting: Sendable, Equatable {
    public let path: ConfigPath
    public let modelName: String?
    public let levels: [String]?

    public init(path: ConfigPath, modelName: String?, levels: [String]?) {
        self.path = path
        self.modelName = modelName
        self.levels = levels
    }
}

public struct FastSetting: Sendable, Equatable {
    public let path: ConfigPath
    public let onValue: ConfigValue
    public let lockedValue: String?
    public let requiresModelTier: Bool

    public init(path: ConfigPath, onValue: ConfigValue, lockedValue: String?, requiresModelTier: Bool) {
        self.path = path
        self.onValue = onValue
        self.lockedValue = lockedValue
        self.requiresModelTier = requiresModelTier
    }
}

public struct PluginItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let path: ConfigPath?
    public let isEnabled: Bool

    public init(id: String, name: String, path: ConfigPath?, isEnabled: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
    }
}

public struct AgentConfig: Sendable, Equatable {
    public var model: ModelSetting
    public var efforts: [EffortSetting]
    public var fast: FastSetting?
    public var choices: [ConfigChoice]
    public var plugins: [PluginItem]
    public var pluginsComplete: Bool
    public var values: [ConfigPath: ConfigValue]

    public init(model: ModelSetting, efforts: [EffortSetting], fast: FastSetting?, choices: [ConfigChoice],
                plugins: [PluginItem], pluginsComplete: Bool, values: [ConfigPath: ConfigValue]) {
        self.model = model
        self.efforts = efforts
        self.fast = fast
        self.choices = choices
        self.plugins = plugins
        self.pluginsComplete = pluginsComplete
        self.values = values
    }
}

public struct ConfigSnapshot: Sendable, Equatable {
    public let config: AgentConfig
    public let version: String?

    public init(config: AgentConfig, version: String?) {
        self.config = config
        self.version = version
    }
}

public struct ConfigSaveResult: Sendable, Equatable {
    public let overrideMessage: String?

    public init(overrideMessage: String?) {
        self.overrideMessage = overrideMessage
    }
}

public enum ConfigValidation: Sendable, Equatable {
    case valid, unchecked
}

public enum ConfigError: Error, Sendable, Equatable {
    case cliNotFound, unsupportedCLI, conflict
    case invalidFile(String), invalidValue(String), readFailed(String), writeFailed(String)
}
