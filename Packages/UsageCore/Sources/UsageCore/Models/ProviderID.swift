public enum ProviderID: String, Sendable, CaseIterable, Codable {
    case claude, codex, grok

    /// Providers with Instructions and Config pages. Grok only reports usage.
    public static let configurable: [ProviderID] = [.claude, .codex]

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        }
    }
}
