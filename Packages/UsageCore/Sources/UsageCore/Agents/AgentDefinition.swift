import Foundation

public enum AgentFieldValue: Sendable, Equatable {
    case text(String)
    case block(String)
}

public struct AgentField: Sendable, Equatable {
    public let key: String
    public let value: AgentFieldValue

    public init(key: String, value: AgentFieldValue) {
        self.key = key
        self.value = value
    }
}

public enum AgentReadError: Sendable, Equatable {
    case notText
    case failed(String)
}

public struct AgentDefinition: Sendable, Equatable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let description: String?
    public let model: String?
    public let fields: [AgentField]
    public let prompt: String?
    public let readError: AgentReadError?
    public let isLineScanned: Bool

    public init(url: URL, name: String, description: String?, model: String?, fields: [AgentField],
                prompt: String?, readError: AgentReadError? = nil, isLineScanned: Bool = false) {
        self.url = url
        self.name = name
        self.description = description
        self.model = model
        self.fields = fields
        self.prompt = prompt
        self.readError = readError
        self.isLineScanned = isLineScanned
    }

    public static func unreadable(url: URL, error: AgentReadError) -> AgentDefinition {
        AgentDefinition(url: url, name: url.deletingPathExtension().lastPathComponent,
                        description: nil, model: nil, fields: [], prompt: nil, readError: error)
    }
}
