public enum ProviderID: String, Sendable, CaseIterable, Codable {
    case claude, codex, grok

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        }
    }
}
