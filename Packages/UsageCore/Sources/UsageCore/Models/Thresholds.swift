public struct Thresholds: Sendable, Equatable {
    public var warning: Int
    public var critical: Int

    public init(warning: Int = 80, critical: Int = 95) {
        self.warning = warning
        self.critical = critical
    }
}

public enum UsageLevel: Sendable, Equatable {
    case normal, warning, critical

    public static func of(_ percent: Double, thresholds: Thresholds) -> UsageLevel {
        if percent >= Double(thresholds.critical) { return .critical }
        if percent >= Double(thresholds.warning) { return .warning }
        return .normal
    }
}
