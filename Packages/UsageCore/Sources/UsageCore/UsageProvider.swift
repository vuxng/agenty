public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var minimumInterval: Duration { get }
    func fetch() async throws(UsageError) -> UsageSnapshot
}

public extension UsageProvider {
    var minimumInterval: Duration { .zero }
}
