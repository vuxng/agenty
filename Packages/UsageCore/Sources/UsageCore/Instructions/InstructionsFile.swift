import Foundation

public typealias InstructionsError = TextFileError

public struct InstructionsFile: Sendable {
    public let provider: ProviderID
    public let url: URL

    public init(provider: ProviderID, home: URL) {
        self.provider = provider
        switch provider {
        case .claude: self.url = home.appendingPathComponent(".claude/CLAUDE.md")
        case .codex: self.url = home.appendingPathComponent(".codex/AGENTS.md")
        case .grok: preconditionFailure("Grok has no instructions file")
        }
    }

    public var fileName: String { url.lastPathComponent }
    public var displayPath: String { "~/.\(provider.rawValue)/\(fileName)" }

    public func read() throws(InstructionsError) -> String? {
        try TextFile(url: url).read()
    }

    public func write(_ text: String) throws(InstructionsError) {
        try TextFile(url: url).write(text)
    }

    public var isOverridden: Bool {
        guard provider == .codex else { return false }
        let override = url.deletingLastPathComponent().appendingPathComponent("AGENTS.override.md")
        guard let data = try? Data(contentsOf: override),
              let text = String(data: data, encoding: .utf8) else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
