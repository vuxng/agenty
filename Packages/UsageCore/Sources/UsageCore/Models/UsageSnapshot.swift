import Foundation

public struct Credits: Sendable, Hashable {
    public var balance: Decimal?
    public var unlimited: Bool

    public init(balance: Decimal?, unlimited: Bool) {
        self.balance = balance
        self.unlimited = unlimited
    }
}

public struct UsageSnapshot: Sendable, Hashable {
    public var provider: ProviderID
    public var plan: String?
    public var windows: [UsageWindow]
    public var credits: Credits?
    public var fetchedAt: Date

    public init(provider: ProviderID, plan: String?, windows: [UsageWindow], credits: Credits?, fetchedAt: Date) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.credits = credits
        self.fetchedAt = fetchedAt
    }
}
