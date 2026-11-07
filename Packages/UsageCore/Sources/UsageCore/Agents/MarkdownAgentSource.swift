import Foundation

public struct MarkdownAgentSource: AgentSource {
    public let provider: ProviderID
    public let directory: AgentDirectory
    private let checksClaudeAgents: Bool

    public static func claude(home: URL) -> MarkdownAgentSource {
        MarkdownAgentSource(provider: .claude,
                            directory: AgentDirectory(url: home.appendingPathComponent(".claude/agents"),
                                                      home: home, fileExtension: "md", recursive: true),
                            checksClaudeAgents: false)
    }

    public static func grok(home: URL) -> MarkdownAgentSource {
        MarkdownAgentSource(provider: .grok,
                            directory: AgentDirectory(url: home.appendingPathComponent(".grok/agents"),
                                                      home: home, fileExtension: "md", recursive: false),
                            checksClaudeAgents: true)
    }

    public func load() async throws(AgentLoadError) -> AgentListing {
        let files = try directory.files()
        var agents: [AgentDefinition] = []
        for url in files ?? [] {
            do {
                guard let text = try TextFile(url: url).read() else { continue }
                if let agent = MarkdownAgentParser.parse(text, url: url) { agents.append(agent) }
            } catch {
                let mapped: AgentReadError
                switch error {
                case .notText: mapped = .notText
                case .readFailed(let message): mapped = .failed(message)
                default: mapped = .failed(String(describing: error))
                }
                agents.append(.unreadable(url: url, error: mapped))
            }
        }
        let usesClaudeAgents = checksClaudeAgents && !((try? AgentDirectory(
            url: directory.home.appendingPathComponent(".claude/agents"), home: directory.home,
            fileExtension: "md", recursive: false).files()) ?? []).isEmpty
        return AgentListing(folderExists: files != nil, agents: agents, usesClaudeAgents: usesClaudeAgents)
    }
}
