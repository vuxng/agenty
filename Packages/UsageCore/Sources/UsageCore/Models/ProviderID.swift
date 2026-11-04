public enum ProviderID: String, Sendable, CaseIterable, Codable {
    case claude, codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}
