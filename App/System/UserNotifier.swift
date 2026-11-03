import Foundation
import UsageCore
import UserNotifications

/// Presents threshold and reset events as system notifications.
/// Holds no stored state; the notification center is looked up per call.
final class UserNotifier: NSObject, UsageNotifying, UNUserNotificationCenterDelegate {
    func deliver(_ events: [UsageEvent], snapshot: UsageSnapshot) async {
        let center = UNUserNotificationCenter.current()
        for event in events {
            let content = UNMutableNotificationContent()
            let identifier: String
            switch event {
            case .crossed(let provider, let kind, let threshold):
                let window = String(localized: Formatting.title(kind))
                content.title = String(localized: "\(provider.displayName) · \(window) at \(threshold)%")
                content.body = Self.resetBody(kind: kind, snapshot: snapshot)
                identifier = "\(provider.rawValue)|\(kind.storageKey)|\(threshold)"
            case .reset(let provider, let kind):
                let window = String(localized: Formatting.title(kind))
                content.title = String(localized: "\(provider.displayName) · \(window) reset")
                if let percent = snapshot.windows.first(where: { $0.kind == kind })?.usedPercent {
                    let value = Int(percent)
                    content.body = String(localized: "Usage is back to \(value)%")
                }
                identifier = "\(provider.rawValue)|\(kind.storageKey)|reset"
            }
            content.sound = .default
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    func requestAuthorizationIfNeeded() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.notificationsEnabled),
              !defaults.bool(forKey: SettingsKey.didRequestNotificationPermission) else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        defaults.set(true, forKey: SettingsKey.didRequestNotificationPermission)
    }

    /// Requests permission only while the system has not been asked yet.
    func requestAuthorizationIfUndetermined() async {
        guard await authorizationStatus() == .notDetermined else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        UserDefaults.standard.set(true, forKey: SettingsKey.didRequestNotificationPermission)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    private static func resetBody(kind: WindowKind, snapshot: UsageSnapshot) -> String {
        guard let resetsAt = snapshot.windows.first(where: { $0.kind == kind })?.resetsAt else { return "" }
        let now = Date()
        let text = String(localized: Formatting.reset(ResetDescription.make(resetsAt: resetsAt, now: now), now: now))
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}
