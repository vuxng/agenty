import AppKit
import SwiftUI
import UsageCore

struct ProviderErrorView: View {
    let provider: ProviderID
    let error: UsageError
    let store: UsageStore
    var onRetryKeychain: @MainActor () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            ProviderErrorContent(provider: provider, error: error, store: store, onRetryKeychain: onRetryKeychain)
        }
    }
}

/// Shared wording and actions; each surface supplies its own icon and container.
struct ProviderErrorContent: View {
    enum Layout { case inline, stacked }

    let provider: ProviderID
    let error: UsageError
    let store: UsageStore
    var onRetryKeychain: @MainActor () -> Void = {}
    var layout: Layout = .inline

    var body: some View {
        Group {
            Text(message).font(layout == .inline ? .caption : .body)
            if layout == .inline { Spacer(minLength: 0) }
            switch error {
            case .cliNotFound:
                Button("Choose path…", action: choosePath).controlSize(.small)
            case .keychainDenied:
                Button("Retry", action: onRetryKeychain).controlSize(.small)
            case .unexpectedFormat:
                Button("Report issue") {
                    if let url = URL(string: "https://github.com/vuxng/agenty/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            default:
                EmptyView()
            }
        }
    }

    private var message: LocalizedStringResource {
        let name = provider.displayName
        switch error {
        case .notLoggedIn:
            switch provider {
            case .claude: return "Not signed in — run `claude`"
            case .codex: return "Not signed in — run `codex login`"
            case .grok: return "Not signed in — run `grok login`"
            }
        case .tokenExpired: return "Session expired — open Claude Code once"
        case .keychainDenied: return "Keychain access denied — allow Agenty to read “Claude Code-credentials”"
        case .cliNotFound: return "\(name) CLI not found"
        case .network: return "Can't reach \(name) — will retry"
        case .rateLimited: return "\(name) is limiting requests — will retry"
        case .unexpectedFormat: return "API format changed"
        }
    }

    @MainActor private func choosePath() {
        guard let path = ExecutablePicker.choose() else { return }
        UserDefaults.standard.set(path, forKey: SettingsKey.providerPath(provider))
        Task { await store.refreshAll(force: true) }
    }
}
