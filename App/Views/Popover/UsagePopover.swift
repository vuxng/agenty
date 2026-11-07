import SwiftUI
import UsageCore

struct UsagePopover: View {
    let store: UsageStore
    var onRetryKeychain: @MainActor () -> Void = {}
    /// nil in previews.
    var updater: Updater?

    var body: some View {
        let summaries = store.summaries
        VStack(alignment: .leading, spacing: 10) {
            if summaries.isEmpty {
                ContentUnavailableView("No providers enabled", systemImage: "gauge")
            } else {
                ForEach(summaries) { summary in
                    ProviderCard(summary: summary, store: store, onRetryKeychain: onRetryKeychain)
                }
            }
            if let updater, let version = updater.availableVersion {
                UpdateBanner(version: version) { updater.checkForUpdates() }
            }
            PopoverFooter(store: store, isStale: summaries.contains(where: \.isStale))
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { Task { await store.refreshIfOlder(than: .seconds(60)) } }
    }
}

// MARK: - Previews

private struct PreviewHost: View {
    let make: () async -> UsageStore
    @State private var store: UsageStore?

    var body: some View {
        Group {
            if let store { UsagePopover(store: store) } else { ProgressView() }
        }
        .task { store = await make() }
    }
}

private struct HangingProvider: UsageProvider {
    let id: ProviderID
    func fetch() async throws(UsageError) -> UsageSnapshot {
        try? await Task.sleep(for: .seconds(3600))
        throw .network(retryAfter: nil)
    }
}

private func previewSnapshot(
    _ id: ProviderID, plan: String? = "pro", windows: [UsageWindow], credits: Credits? = nil,
    age: TimeInterval = 0, email: String? = nil
) -> UsageSnapshot {
    UsageSnapshot(provider: id, plan: plan, windows: windows, credits: credits,
                  fetchedAt: Date().addingTimeInterval(-age), accountEmail: email)
}

private func win(_ kind: WindowKind, _ pct: Double, hours: Double) -> UsageWindow {
    UsageWindow(kind: kind, usedPercent: pct, resetsAt: Date().addingTimeInterval(hours * 3600))
}

private let loadedResults: [ProviderID: Result<UsageSnapshot, UsageError>] = [
    .claude: .success(previewSnapshot(.claude, windows: [
        win(.session5h, 45, hours: 2.2), win(.weekly, 62, hours: 72), win(.weeklyModel("Opus"), 84, hours: 72),
    ], email: "someone@example.com")),
    .codex: .success(previewSnapshot(.codex, plan: "plus", windows: [win(.weekly, 18, hours: 200)],
                                     credits: Credits(balance: 61862.97, unlimited: false),
                                     email: "a.very.long.address.for.truncation@example.com")),
    .grok: .success(previewSnapshot(.grok, plan: "SuperGrok Plus", windows: [win(.weekly, 7, hours: 120)])),
]

#Preview("Loaded") { PreviewHost { await previewStore(loadedResults) } }

#Preview("Loading") {
    PreviewHost {
        let store = UsageStore(
            providers: [HangingProvider(id: .claude), HangingProvider(id: .codex)],
            configuration: StoreConfiguration(enabled: [.claude, .codex]),
            defaults: UserDefaults(suiteName: "io.github.vuxng.Agenty.preview") ?? .standard
        )
        Task { await store.refreshAll() }
        return store
    }
}

#Preview("Errors") {
    PreviewHost {
        await previewStore([
            .claude: .failure(.notLoggedIn),
            .codex: .failure(.cliNotFound),
            .grok: .failure(.notLoggedIn),
        ])
    }
}

#Preview("Token expired / network") {
    PreviewHost {
        await previewStore([.claude: .failure(.tokenExpired), .codex: .failure(.network(retryAfter: nil))])
    }
}

#Preview("Stale") {
    PreviewHost {
        await previewStore([
            .claude: .success(previewSnapshot(.claude, windows: [win(.weekly, 62, hours: 72)], age: 7200)),
        ])
    }
}

#Preview("No windows") {
    PreviewHost { await previewStore([.claude: .success(previewSnapshot(.claude, windows: []))]) }
}

#Preview("No providers") { PreviewHost { await previewStore([:]) } }
