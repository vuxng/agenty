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
            HStack(spacing: 2) {
                Button { Task { await store.refreshAll(force: true) } } label: {
                    FooterIcon(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(Text("Refresh"))
                .help(Text("Refresh"))
                SettingsLink { FooterIcon(systemName: "gearshape") }
                    .accessibilityLabel(Text("Settings"))
                    .help(Text("Settings"))
                Button { NSApplication.shared.terminate(nil) } label: {
                    FooterIcon(systemName: "power")
                }
                .accessibilityLabel(Text("Quit Agenty"))
                .help(Text("Quit Agenty"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}

/// A bare icon; the invisible frame keeps the click target comfortable.
private struct FooterIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .frame(width: 24, height: 24)
            .contentShape(.rect)
    }
}
