import SwiftUI
import UsageCore

struct UsageProviderCard: View {
    let summary: ProviderSummary
    let store: UsageStore
    let onRetryKeychain: @MainActor () -> Void

    @AppStorage(SettingsKey.showAccountEmail) private var showAccountEmail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if let snapshot = summary.state.snapshot {
                if let error = summary.displayError, !isTransient(error) {
                    notice(error)
                }
                VStack(alignment: .leading, spacing: 24) {
                    if let window = summary.window {
                        UsageHero(window: window, level: summary.level)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "gauge.with.dots.needle.0percent")
                                .font(.title).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("No active limits")
                        }
                        .frame(minHeight: 160, alignment: .leading)
                    }
                    Divider()
                    details(snapshot)
                }
                .opacity(summary.displayError == nil ? 1 : 0.55)
                if let error = summary.displayError, isTransient(error) {
                    notice(error)
                }
            } else if let error = summary.displayError {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: errorSymbol(error))
                        .font(.title).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    ProviderErrorContent(
                        provider: summary.provider, error: error, store: store,
                        onRetryKeychain: onRetryKeychain, layout: .stacked
                    )
                }
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            ProviderStyle.brandLogo(summary.provider)
                .resizable().scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.provider.displayName).font(.title3.weight(.semibold))
                if showAccountEmail, let email = summary.state.snapshot?.accountEmail {
                    Text(email)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if case .loading = summary.state, summary.displayError != nil {
                ProgressView().controlSize(.mini)
            }
            if let plan = summary.state.snapshot?.plan {
                Text(plan.capitalized)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.secondary, in: .capsule)
            }
        }
    }

    private func details(_ snapshot: UsageSnapshot) -> some View {
        // Remove only the hero; preserve the remaining windows' API order.
        var windows = snapshot.windows
        if let hero = summary.window, let index = windows.firstIndex(of: hero) {
            windows.remove(at: index)
        }
        return VStack(spacing: 8) {
            ForEach(Array(windows.enumerated()), id: \.element.kind) { index, window in
                let previous = index == 0 ? summary.window : windows[index - 1]
                VStack(spacing: 8) {
                    if index > 0 { Divider() }
                    UsageDetailRow(
                        window: window,
                        level: UsageLevel.of(window.usedPercent, thresholds: store.configuration.thresholds),
                        showsReset: previous.map { !window.sharesReset(with: $0) } ?? true
                    )
                }
            }
            if let credits = snapshot.credits, let text = Formatting.credits(credits) {
                Text(text)
                    .font(.body).monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
    }

    private func notice(_ error: UsageError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isNetwork(error) ? "wifi.slash" : "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            ProviderErrorContent(
                provider: summary.provider, error: error, store: store,
                onRetryKeychain: onRetryKeychain
            )
        }
    }

    private func isTransient(_ error: UsageError) -> Bool {
        switch error {
        case .network, .rateLimited: true
        default: false
        }
    }

    private func isNetwork(_ error: UsageError) -> Bool {
        if case .network = error { true } else { false }
    }

    private func errorSymbol(_ error: UsageError) -> String {
        switch error {
        case .notLoggedIn, .tokenExpired: "person.crop.circle.badge.exclamationmark"
        case .cliNotFound: "terminal"
        case .keychainDenied: "lock"
        case .unexpectedFormat: "questionmark.diamond"
        case .network: "wifi.slash"
        case .rateLimited: "exclamationmark.triangle.fill"
        }
    }
}

private struct UsageHero: View {
    let window: UsageWindow
    let level: UsageLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                UsageLevelIcon(level: level)
                Text(Formatting.title(window.kind)).font(.headline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: String(Int(window.usedPercent.rounded())))
                    .font(.system(size: 112, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Text(verbatim: "%").font(.largeTitle.weight(.thin)).fontDesign(.rounded)
            }
            .foregroundStyle(level.color ?? .primary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(Int(window.usedPercent.rounded()))%"))
            if let resetsAt = window.resetsAt {
                UsageResetText(resetsAt: resetsAt)
            }
        }
    }
}

private struct UsageDetailRow: View {
    let window: UsageWindow
    let level: UsageLevel
    let showsReset: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                UsageLevelIcon(level: level)
                Text(Formatting.title(window.kind)).font(.body)
                Spacer(minLength: 8)
                if showsReset, let resetsAt = window.resetsAt {
                    UsageResetText(resetsAt: resetsAt)
                }
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.body.weight(.semibold)).monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            GeometryReader { geometry in
                Capsule().fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule().fill(level.color ?? .primary)
                            .frame(width: geometry.size.width * window.fraction)
                    }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
    }
}

private struct UsageResetText: View {
    let resetsAt: Date

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(Formatting.reset(.make(resetsAt: resetsAt, now: context.date), now: context.date))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

private struct UsageLevelIcon: View {
    let level: UsageLevel

    var body: some View {
        switch level {
        case .normal: EmptyView()
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).accessibilityLabel(Text("Warning"))
        case .critical:
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.red).accessibilityLabel(Text("Critical"))
        }
    }
}

// MARK: - Previews

#if DEBUG
/// Drives real store transitions without credentials, subprocesses, or network requests.
private actor CardPreviewProvider: UsageProvider {
    let id: ProviderID
    let snapshot: UsageSnapshot?
    let error: UsageError?
    let loading: Bool
    private var fetchedSnapshot = false

    init(id: ProviderID, snapshot: UsageSnapshot?, error: UsageError?, loading: Bool) {
        self.id = id
        self.snapshot = snapshot
        self.error = error
        self.loading = loading
    }

    func fetch() async throws(UsageError) -> UsageSnapshot {
        if let snapshot, !fetchedSnapshot {
            fetchedSnapshot = true
            return snapshot
        }
        if loading {
            try? await Task.sleep(for: .seconds(3600))
        }
        if let error { throw error }
        if let snapshot { return snapshot }
        throw .network(retryAfter: nil)
    }
}

private struct UsageCardPreview: View {
    var provider: ProviderID = .claude
    var percent: Double? = 62
    var error: UsageError? = nil
    var loading = false
    var emptyWindows = false
    var credits: Credits? = Credits(balance: 61862.97, unlimited: false)
    var thresholds = Thresholds()

    @State private var store: UsageStore?

    var body: some View {
        Group {
            if let store, let summary = store.summaries.first {
                UsageProviderCard(summary: summary, store: store, onRetryKeychain: {})
            } else {
                ProgressView()
            }
        }
        .frame(width: 468)
        .padding(24)
        .background { AmbientField(page: .usage, selected: provider) }
        .task {
            let reset = Date().addingTimeInterval(86_400)
            let snapshot = percent.map { percent in
                UsageSnapshot(
                    provider: provider, plan: "pro",
                    windows: emptyWindows ? [] : [
                        UsageWindow(kind: .session5h, usedPercent: 12, resetsAt: Date().addingTimeInterval(3600)),
                        UsageWindow(kind: .weekly, usedPercent: percent, resetsAt: reset),
                        UsageWindow(kind: .weeklyModel("Opus"), usedPercent: 10, resetsAt: reset),
                    ],
                    credits: credits,
                    fetchedAt: Date().addingTimeInterval(error == nil ? 0 : -7200),
                    accountEmail: "preview@example.com"
                )
            }
            let source = CardPreviewProvider(id: provider, snapshot: snapshot, error: error, loading: loading)
            let previewStore = UsageStore(
                providers: [source],
                configuration: StoreConfiguration(enabled: [provider], thresholds: thresholds, notificationsEnabled: false),
                defaults: UserDefaults(suiteName: "io.github.vuxng.Agenty.usage-card-preview")!
            )
            store = previewStore
            await previewStore.refreshAll()
            if snapshot != nil, error != nil || loading {
                await previewStore.refreshAll(force: true)
            }
        }
    }
}

#Preview("Normal") { UsageCardPreview() }
#Preview("Warning") { UsageCardPreview(percent: 84) }
#Preview("Critical") { UsageCardPreview(percent: 97) }
#Preview("Custom warning threshold") {
    UsageCardPreview(percent: 62, thresholds: Thresholds(warning: 50, critical: 70))
}
#Preview("Network with cached data") { UsageCardPreview(error: .network(retryAfter: nil)) }
#Preview("Rate limited with cached data") { UsageCardPreview(error: .rateLimited(retryAfter: nil)) }
#Preview("Other error with cached data") { UsageCardPreview(error: .tokenExpired) }
#Preview("Loading without data") { UsageCardPreview(percent: nil, loading: true) }
#Preview("Refreshing cached data") { UsageCardPreview(loading: true) }
#Preview("No limits, with credits") { UsageCardPreview(provider: .codex, emptyWindows: true) }
#Preview("No active limits") { UsageCardPreview(emptyWindows: true, credits: nil) }
#Preview("Not signed in") { UsageCardPreview(percent: nil, error: .notLoggedIn) }
#Preview("Session expired") { UsageCardPreview(percent: nil, error: .tokenExpired) }
#Preview("CLI not found") { UsageCardPreview(provider: .codex, percent: nil, error: .cliNotFound) }
#Preview("Keychain denied") { UsageCardPreview(percent: nil, error: .keychainDenied) }
#Preview("API format changed") { UsageCardPreview(percent: nil, error: .unexpectedFormat("Preview response")) }
#Preview("Network without data") { UsageCardPreview(percent: nil, error: .network(retryAfter: nil)) }
#Preview("Rate limited without data") { UsageCardPreview(percent: nil, error: .rateLimited(retryAfter: nil)) }
#endif
