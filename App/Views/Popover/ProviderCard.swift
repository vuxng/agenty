import SwiftUI
import UsageCore

struct ProviderCard: View {
    let summary: ProviderSummary
    let store: UsageStore
    var onRetryKeychain: @MainActor () -> Void = {}

    @AppStorage(SettingsKey.showAccountEmail) private var showAccountEmail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let error = visibleError {
                ProviderErrorView(provider: summary.provider, error: error, store: store, onRetryKeychain: onRetryKeychain)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleRow
            if showAccountEmail, let email = summary.state.snapshot?.accountEmail {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 20) // lines up with the provider name, past the 14 pt logo + 6 pt gap
            }
        }
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            ProviderStyle.brandLogo(summary.provider)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .accessibilityHidden(true) // the provider name follows
            Text(summary.provider.displayName).font(.headline)
            Spacer()
            if case .loading = summary.state, visibleError != nil {
                ProgressView().controlSize(.mini)
            }
            if let plan = summary.state.snapshot?.plan {
                Text(plan.capitalized)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    /// Network errors with a last snapshot show no row (the footer turns orange instead).
    private var visibleError: UsageError? {
        guard let error = summary.displayError else { return nil }
        if case .network = error, summary.state.snapshot != nil { return nil }
        return error
    }

    @ViewBuilder private var content: some View {
        if let snapshot = summary.state.snapshot {
            if snapshot.windows.isEmpty {
                if visibleError == nil {
                    Text("No active limits").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    WindowRow(
                        window: window,
                        level: UsageLevel.of(window.usedPercent, thresholds: store.configuration.thresholds)
                    )
                }
            }
            if let credits = snapshot.credits, let text = Formatting.credits(credits) {
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        } else if visibleError == nil {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        }
    }
}
