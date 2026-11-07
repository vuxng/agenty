import Foundation

public enum AgentLoadError: Error, Sendable, Equatable {
    case cliNotFound
    case failed(String)
}

public struct AgentListing: Sendable, Equatable {
    public let folderExists: Bool
    public let agents: [AgentDefinition]
    public let usesClaudeAgents: Bool

    public init(folderExists: Bool, agents: [AgentDefinition], usesClaudeAgents: Bool = false) {
        self.folderExists = folderExists
        self.agents = agents.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
        self.usesClaudeAgents = usesClaudeAgents
    }
}

public protocol AgentSource: Sendable {
    var provider: ProviderID { get }
    var directory: AgentDirectory { get }
    func load() async throws(AgentLoadError) -> AgentListing
}
