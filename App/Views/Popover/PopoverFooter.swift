import AppKit
import SwiftUI
import UsageCore

struct PopoverFooter: View {
    let store: UsageStore
    let isStale: Bool

    /// "DEV" on Debug builds ("Agenty Dev"), so they can't be mistaken for the installed Agenty.
    private static let buildBadge: String? = {
        #if DEBUG
        return "DEV"
        #else
        return nil
        #endif
    }()

    var body: some View {
        HStack(spacing: 8) {
            if let badge = Self.buildBadge {
                Text(verbatim: badge)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
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
            .accessibilityLabel(Text("Refresh"))
            .help(Text("Refresh"))
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.glass)
                .accessibilityLabel(Text("Settings"))
                .help(Text("Settings"))
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Text("Quit Agenty"))
            .help(Text("Quit Agenty"))
        }
    }
}
