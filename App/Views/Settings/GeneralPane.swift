import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    /// nil in previews, so Sparkle is never started there.
    var updater: Updater?

    @AppStorage(SettingsKey.refreshMinutes) private var refreshMinutes = 5
    @AppStorage(SettingsKey.menuBarStyle) private var menuBarStyle = MenuBarStyle.bars.rawValue
    @AppStorage(SettingsKey.showAccountEmail) private var showAccountEmail = false

    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
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

            Section("Display") {
                Picker("Menu bar shows", selection: $menuBarStyle) {
                    Text("Bars").tag(MenuBarStyle.bars.rawValue)
                    Text("Highest percentage").tag(MenuBarStyle.single.rawValue)
                    Text("Each provider").tag(MenuBarStyle.perProvider.rawValue)
                }
                Toggle("Show account email", isOn: $showAccountEmail)
            }

            if let updater {
                UpdatesSection(updater: updater)
            }
        }
        .settingsPaneLayout()
        .onAppear { loginStatus = LoginItem.status }
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
}

private struct UpdatesSection: View {
    @Bindable var updater: Updater

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                .disabled(!updater.isEnabled)
            LabeledContent("Version") {
                HStack {
                    Text(verbatim: "\(Self.shortVersion) (\(Self.buildNumber))")
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.isEnabled || !updater.canCheckForUpdates)
                }
            }
        } header: {
            Text("Updates")
        } footer: {
            if !updater.isEnabled {
                Text("Updates are off in debug builds")
            }
        }
    }

    private static let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    private static let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
}
