import Foundation

public enum ResetDescription: Sendable, Equatable {
    case relative(Duration)
    case absolute(Date)
    case overdue

    public static func make(resetsAt: Date, now: Date) -> ResetDescription {
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return .overdue }
        if interval >= 86_400 { return .absolute(resetsAt) }
        let minuteAligned = Int(interval) / 60 * 60
        return .relative(.seconds(minuteAligned))
    }
}
