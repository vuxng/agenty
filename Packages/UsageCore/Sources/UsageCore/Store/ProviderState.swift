public enum ProviderState: Sendable, Equatable {
    case idle
    case loading(last: UsageSnapshot?)
    case loaded(UsageSnapshot)
    case failed(UsageError, last: UsageSnapshot?)

    public var snapshot: UsageSnapshot? {
        switch self {
        case .idle: nil
        case .loading(let last): last
        case .loaded(let s): s
        case .failed(_, let last): last
        }
    }

    public var error: UsageError? {
        if case .failed(let e, _) = self { e } else { nil }
    }
}

public struct ProviderSummary: Sendable, Equatable, Identifiable {
    public let provider: ProviderID
    public let state: ProviderState
    public let window: UsageWindow?
    public let level: UsageLevel
    public let isStale: Bool

    public var id: ProviderID { provider }
    public var hasError: Bool { state.error != nil }
}

public protocol UsageNotifying: Sendable {
    func deliver(_ events: [UsageEvent], snapshot: UsageSnapshot) async
}
