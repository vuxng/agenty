import Foundation

public struct UsageWindow: Sendable, Hashable {
    public var kind: WindowKind
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(kind: WindowKind, usedPercent: Double, resetsAt: Date?) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// `usedPercent` as a 0...1 fraction, clamped.
    public var fraction: Double { min(max(usedPercent / 100, 0), 1) }

    /// Whether both windows reset within the same minute, the finest unit the UI shows.
    /// The server's timestamps for one reset can differ by a fraction of a second.
    public func sharesReset(with other: UsageWindow) -> Bool {
        guard let resetsAt, let otherResetsAt = other.resetsAt else { return false }
        return abs(resetsAt.timeIntervalSince(otherResetsAt)) < 60
    }

    /// Highest `usedPercent`; ties go to the later `resetsAt` (nil counts as earliest).
    public static func mostConstrained(in windows: [UsageWindow]) -> UsageWindow? {
        windows.reduce(nil) { best, w in
            guard let best else { return w }
            if w.usedPercent != best.usedPercent { return w.usedPercent > best.usedPercent ? w : best }
            return (w.resetsAt ?? .distantPast) > (best.resetsAt ?? .distantPast) ? w : best
        }
    }
}
