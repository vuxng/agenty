import AppKit
import SwiftUI
import UsageCore

struct ProviderErrorView: View {
    let provider: ProviderID
    let error: UsageError
    let store: UsageStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption)
            Spacer(minLength: 0)
            switch error {
            case .cliNotFound:
                Button("Choose path…", action: choosePath).controlSize(.small)
            case .unexpectedFormat:
                Button("Report issue") {
                    if let url = URL(string: "https://github.com/vuxng/llm-usage/issues/new") {
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
        case .cliNotFound: return "\(name) CLI not found"
        case .network: return "Can't reach \(name) — will retry"
        case .unexpectedFormat: return "API format changed"
        }
    }

    @MainActor private func choosePath() {
        guard let path = ExecutablePicker.choose() else { return }
        UserDefaults.standard.set(path, forKey: SettingsKey.providerPath(provider))
        Task { await store.refreshAll(force: true) }
    }
}
