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
    /// Lowercase plan ids ("max") get a capital; names the provider already styled ("SuperGrok Plus") stay as they are.
    public var displayPlan: String? { plan.map { $0 == $0.lowercased() ? $0.capitalized : $0 } }
    public var windows: [UsageWindow]
    public var credits: Credits?
    public var fetchedAt: Date
    /// Email of the signed-in account; nil when the provider didn't say.
    public var accountEmail: String?

    public init(provider: ProviderID, plan: String?, windows: [UsageWindow], credits: Credits?, fetchedAt: Date,
                accountEmail: String? = nil) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.credits = credits
        self.fetchedAt = fetchedAt
        self.accountEmail = accountEmail
    }
}
