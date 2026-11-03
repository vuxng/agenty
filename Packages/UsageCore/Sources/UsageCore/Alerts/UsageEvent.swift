public enum UsageEvent: Sendable, Equatable {
    case crossed(ProviderID, WindowKind, threshold: Int)
    case reset(ProviderID, WindowKind)
}

/// Highest threshold already notified per window; persisted so restarts never re-notify.
public struct NotifiedLevels: Sendable, Equatable, Codable {
    public var levels: [String: Int]

    public init(levels: [String: Int] = [:]) {
        self.levels = levels
    }

    public static func key(_ p: ProviderID, _ k: WindowKind) -> String {
        "\(p.rawValue)|\(k.storageKey)"
    }
}
