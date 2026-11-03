import AppKit
import SwiftUI
import UsageCore

struct PopoverFooter: View {
    let store: UsageStore
    let isStale: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let last = store.lastRefreshAt {
                    Text("Updated \(last, format: .dateTime.hour().minute())")
                } else {
                    Text("Updated —")
                }
            }
            .font(.caption)
            .foregroundStyle(isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            if store.isRefreshing { ProgressView().controlSize(.small) }
            Spacer()
            Button { Task { await store.refreshAll(force: true) } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.glass)
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.glass)
        }
    }
}
