public struct StoreConfiguration: Sendable, Equatable {
    public var enabled: Set<ProviderID>
    public var refreshInterval: Duration
    public var thresholds: Thresholds
    public var notificationsEnabled: Bool
    public var notifyOnReset: Bool

    public init(
        enabled: Set<ProviderID> = Set(ProviderID.allCases),
        refreshInterval: Duration = .seconds(300),
        thresholds: Thresholds = Thresholds(),
        notificationsEnabled: Bool = true,
        notifyOnReset: Bool = true
    ) {
        self.enabled = enabled
        self.refreshInterval = refreshInterval
        self.thresholds = thresholds
        self.notificationsEnabled = notificationsEnabled
        self.notifyOnReset = notifyOnReset
    }
}
