import SwiftUI
import UsageCore

struct UsagePage: View {
    let store: UsageStore
    let onRetryKeychain: @MainActor () -> Void

    var body: some View {
        let summaries = store.summaries
        Group {
            if summaries.isEmpty {
                ContentUnavailableView("No providers enabled", systemImage: "gauge")
            } else {
                ScrollView {
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(summaries) { summary in
                            UsageProviderCard(summary: summary, store: store, onRetryKeychain: onRetryKeychain)
                                .frame(maxWidth: summaries.count == 1 ? 468 : .infinity)
                        }
                    }
                    .frame(maxWidth: 960)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.center, for: .alignment)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { Task { await store.refreshIfOlder(than: .seconds(60)) } }
    }
}

#if DEBUG
private struct UsagePagePreview: View {
    var enabled: Set<ProviderID> = [.claude, .codex]
    @State private var store: UsageStore?

    var body: some View {
        Group {
            if let store {
                UsagePage(store: store, onRetryKeychain: {})
            } else {
                ProgressView()
            }
        }
        .background { AmbientField(page: .usage, selected: .claude) }
        .task {
            let results: [ProviderID: Result<UsageSnapshot, UsageError>] = [
                .claude: .success(.preview(.claude, percent: 62, plan: "max")),
                .codex: .success(.preview(.codex, percent: 18, plan: "plus")),
            ]
            store = await previewStore(results.filter { enabled.contains($0.key) })
        }
    }
}

#Preview("Two providers — minimum window") { UsagePagePreview().frame(width: 860, height: 580) }
#Preview("Two providers — large window") { UsagePagePreview().frame(width: 1400, height: 900) }
#Preview("One provider — fixed width") { UsagePagePreview(enabled: [.claude]).frame(width: 980, height: 640) }
#Preview("No providers enabled") {
    UsagePage(store: UsageStore(providers: [], configuration: StoreConfiguration(enabled: [])), onRetryKeychain: {})
}
#endif
