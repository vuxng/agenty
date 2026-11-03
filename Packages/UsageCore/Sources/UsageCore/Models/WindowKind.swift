public enum WindowKind: Sendable, Hashable {
    case session5h
    case weekly
    case weeklyModel(String)
    case billingPeriod
    case other(minutes: Int)

    public var storageKey: String {
        switch self {
        case .session5h: "session5h"
        case .weekly: "weekly"
        case .weeklyModel(let name): "weeklyModel:\(name)"
        case .billingPeriod: "billingPeriod"
        case .other(let minutes): "other:\(minutes)"
        }
    }
}
