import Foundation
import UsageCore

enum MenuBarStyle: String, CaseIterable {
    case bars, single, perProvider
}

/// A toolbar pane of the settings window.
enum SettingsPane: String {
    case general, providers, notifications
}

enum SettingsKey {
    static let mainPage = "mainPage"
    static let settingsPane = "settingsPane"
    static let menuBarStyle = "menuBarStyle"
    static let refreshMinutes = "refreshMinutes"
    static let notificationsEnabled = "notificationsEnabled"
    static let warningThreshold = "warningThreshold"
    static let criticalThreshold = "criticalThreshold"
    static let notifyOnReset = "notifyOnReset"
    static let didRequestNotificationPermission = "didRequestNotificationPermission"
    static let showAccountEmail = "showAccountEmail"

    static func providerEnabled(_ id: ProviderID) -> String { "provider.\(id.rawValue).enabled" }
    static func providerPath(_ id: ProviderID) -> String { "provider.\(id.rawValue).path" }
}

enum AppDefaults {
    static let refreshChoices = [1, 2, 5, 10, 15]

    /// Non-persistent registration defaults.
    static func register(in defaults: UserDefaults) {
        var values: [String: Any] = [
            SettingsKey.menuBarStyle: MenuBarStyle.bars.rawValue,
            SettingsKey.refreshMinutes: 5,
            SettingsKey.notificationsEnabled: true,
            SettingsKey.warningThreshold: 80,
            SettingsKey.criticalThreshold: 95,
            SettingsKey.notifyOnReset: true,
            SettingsKey.didRequestNotificationPermission: false,
            SettingsKey.showAccountEmail: false, // off by default: the popover may be on a shared screen
        ]
        for id in ProviderID.allCases {
            values[SettingsKey.providerEnabled(id)] = true
            values[SettingsKey.providerPath(id)] = ""
        }
        defaults.register(defaults: values)
    }

    /// Reads only; never writes.
    static func configuration(from defaults: UserDefaults) -> StoreConfiguration {
        let enabled = Set(ProviderID.allCases.filter { defaults.bool(forKey: SettingsKey.providerEnabled($0)) })
        let minutes = defaults.integer(forKey: SettingsKey.refreshMinutes)
        let interval = Duration.seconds(60 * (refreshChoices.contains(minutes) ? minutes : 5))

        var warning = min(max(defaults.integer(forKey: SettingsKey.warningThreshold), 1), 100)
        var critical = min(max(defaults.integer(forKey: SettingsKey.criticalThreshold), 1), 100)
        if warning >= critical { (warning, critical) = (80, 95) }

        return StoreConfiguration(
            enabled: enabled,
            refreshInterval: interval,
            thresholds: Thresholds(warning: warning, critical: critical),
            notificationsEnabled: defaults.bool(forKey: SettingsKey.notificationsEnabled),
            notifyOnReset: defaults.bool(forKey: SettingsKey.notifyOnReset)
        )
    }
}
