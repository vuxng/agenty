import Foundation
import UsageCore

struct PreviewUsageProvider: UsageProvider {
    let id: ProviderID
    let result: Result<UsageSnapshot, UsageError>

    func fetch() async throws(UsageError) -> UsageSnapshot {
        try result.get()
    }
}

@MainActor
func previewStore(_ results: [ProviderID: Result<UsageSnapshot, UsageError>]) async -> UsageStore {
    let providers = results.map { PreviewUsageProvider(id: $0.key, result: $0.value) }
    let store = UsageStore(
        providers: providers,
        configuration: StoreConfiguration(enabled: Set(results.keys)),
        defaults: UserDefaults(suiteName: "io.github.vuxng.LLMUsage.preview") ?? .standard
    )
    await store.refreshAll()
    return store
}

extension UsageSnapshot {
    static func preview(_ provider: ProviderID, percent: Double, plan: String? = "Pro") -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            plan: plan,
            windows: [UsageWindow(kind: .weekly, usedPercent: percent, resetsAt: Date().addingTimeInterval(86_400))],
            credits: nil,
            fetchedAt: Date()
        )
    }
}
