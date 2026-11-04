import AppKit
import SwiftUI
import UsageCore

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        SettingsPanes(
            providers: model.store.registeredProviders, locator: model.locator,
            notifier: model.notifier, updater: model.updater
        )
    }
}

struct SettingsPanes: View {
    let providers: [ProviderID]
    let locator: CLILocator
    /// nil in previews, so no real notification center is touched.
    var notifier: UserNotifier?
    /// nil in previews, so Sparkle is never started there.
    var updater: Updater?

    // Stored so the window reopens on the pane used last.
    @AppStorage(SettingsKey.settingsPane) private var pane = SettingsPane.general

    var body: some View {
        TabView(selection: $pane) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralPane(updater: updater)
            }
            Tab("Providers", systemImage: "square.stack.3d.up", value: .providers) {
                ProvidersPane(providers: providers, locator: locator)
            }
            Tab("Notifications", systemImage: "bell", value: .notifications) {
                NotificationsPane(notifier: notifier)
            }
        }
        .onAppear { NSApp.activate() }
    }
}

extension View {
    /// Shared by every pane. The height follows the content, so the window fits the current pane.
    func settingsPaneLayout() -> some View {
        formStyle(.grouped)
            .frame(width: 460)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PreviewShellLookup: LoginShellLookup {
    func commandPath(for name: String) async -> String? { nil }
}

#Preview {
    SettingsPanes(
        providers: [.claude, .codex],
        locator: CLILocator(home: URL(filePath: NSHomeDirectory()), shell: PreviewShellLookup())
    )
}
