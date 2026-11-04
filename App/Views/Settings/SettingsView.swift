import AppKit
import ServiceManagement
import SwiftUI
import UsageCore
import UserNotifications

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        SettingsForm(
            providers: model.store.registeredProviders, locator: model.locator,
            notifier: model.notifier, updater: model.updater
        )
    }
}

struct SettingsForm: View {
    let providers: [ProviderID]
    let locator: CLILocator
    /// nil in previews, so no real notification center is touched.
    var notifier: UserNotifier?
    /// nil in previews, so Sparkle is never started there.
    var updater: Updater?

    @AppStorage(SettingsKey.menuBarStyle) private var menuBarStyle = MenuBarStyle.bars.rawValue
    @AppStorage(SettingsKey.refreshMinutes) private var refreshMinutes = 5
    @AppStorage(SettingsKey.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(SettingsKey.warningThreshold) private var warning = 80
    @AppStorage(SettingsKey.criticalThreshold) private var critical = 95
    @AppStorage(SettingsKey.notifyOnReset) private var notifyOnReset = true

    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: launchAtLogin)
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Approve Agenty in System Settings › Login Items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Picker("Refresh every", selection: $refreshMinutes) {
                    ForEach(AppDefaults.refreshChoices, id: \.self) { Text("\($0) min").tag($0) }
                }
            }

            Section("Menu bar") {
                Picker("Show", selection: $menuBarStyle) {
                    Text("Bars (default)").tag(MenuBarStyle.bars.rawValue)
                    Text("Highest percentage").tag(MenuBarStyle.single.rawValue)
                    Text("Each provider").tag(MenuBarStyle.perProvider.rawValue)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Providers") {
                ForEach(providers, id: \.self) { provider in
                    ProviderToggle(provider: provider)
                    if provider == .codex {
                        ProviderPathRow(provider: provider, locator: locator)
                    }
                }
            }

            Section("Notifications") {
                Toggle("Notify near limits", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, on in
                        guard on, let notifier else { return }
                        Task {
                            await notifier.requestAuthorizationIfUndetermined()
                            notificationStatus = await notifier.authorizationStatus()
                        }
                    }
                if notificationStatus == .denied {
                    HStack {
                        Text("Notifications disabled in System Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                    }
                }
                Stepper("Warn at \(warning)%", value: warningBinding, in: warningRange, step: 5)
                Stepper("Critical at \(critical)%", value: criticalBinding, in: criticalRange, step: 5)
                Toggle("Notify when limits reset", isOn: $notifyOnReset)
            }

            if let updater {
                UpdatesSection(updater: updater)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            NSApp.activate()
            loginStatus = LoginItem.status
        }
        .task { notificationStatus = await notifier?.authorizationStatus() }
        .alert("Couldn't change launch at login", isPresented: loginErrorShown) {
            Button("OK") { loginError = nil }
        } message: {
            Text(verbatim: loginError ?? "")
        }
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled },
            set: { on in
                do {
                    try LoginItem.setEnabled(on)
                } catch {
                    loginError = error.localizedDescription
                }
                loginStatus = LoginItem.status
            }
        )
    }

    private var loginErrorShown: Binding<Bool> {
        Binding(get: { loginError != nil }, set: { if !$0 { loginError = nil } })
    }

    // Ranges never become empty: stored values are clamped for display.
    private var warningRange: ClosedRange<Int> {
        50...max(50, critical - 5)
    }

    private var criticalRange: ClosedRange<Int> {
        min(100, warning + 5)...100
    }

    private var warningBinding: Binding<Int> {
        Binding(
            get: { min(max(warning, warningRange.lowerBound), warningRange.upperBound) },
            set: { warning = $0 }
        )
    }

    private var criticalBinding: Binding<Int> {
        Binding(
            get: { min(max(critical, criticalRange.lowerBound), criticalRange.upperBound) },
            set: { critical = $0 }
        )
    }
}

private struct UpdatesSection: View {
    @Bindable var updater: Updater

    var body: some View {
        Section("Updates") {
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                .disabled(!updater.isEnabled)
            HStack {
                Text("Version \(Self.shortVersion) (\(Self.buildNumber))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.isEnabled || !updater.canCheckForUpdates)
            }
            if !updater.isEnabled {
                Text("Updates are off in debug builds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private static let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
}

private struct ProviderToggle: View {
    let provider: ProviderID
    @AppStorage private var enabled: Bool

    init(provider: ProviderID) {
        self.provider = provider
        _enabled = AppStorage(wrappedValue: true, SettingsKey.providerEnabled(provider))
    }

    var body: some View {
        Toggle(isOn: $enabled) { Text(provider.displayName) }
    }
}

private struct PreviewShellLookup: LoginShellLookup {
    func commandPath(for name: String) async -> String? { nil }
}

#Preview {
    SettingsForm(
        providers: [.claude, .codex],
        locator: CLILocator(home: URL(filePath: NSHomeDirectory()), shell: PreviewShellLookup())
    )
}
