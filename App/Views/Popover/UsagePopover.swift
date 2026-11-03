import SwiftUI
import UsageCore

/// Placeholder; replaced in Task 12.
struct UsagePopover: View {
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.summaries) { summary in
                Text("\(summary.provider.displayName): \(summary.window?.usedPercent ?? -1)% \(String(describing: summary.state.error))")
            }
            Button("Refresh") {
                Task { await store.refreshAll(force: true) }
            }
        }
        .padding()
        .frame(minWidth: 280)
    }
}

#Preview {
    @Previewable @State var store: UsageStore?
    Group {
        if let store { UsagePopover(store: store) } else { ProgressView() }
    }
    .task {
        store = await previewStore([
            .claude: .success(.preview(.claude, percent: 42)),
            .codex: .failure(.notLoggedIn),
        ])
    }
}
