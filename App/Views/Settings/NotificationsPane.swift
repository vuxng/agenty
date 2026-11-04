import AppKit
import SwiftUI
import UserNotifications

struct NotificationsPane: View {
    /// nil in previews, so no real notification center is touched.
    var notifier: UserNotifier?

    @AppStorage(SettingsKey.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(SettingsKey.notifyOnReset) private var notifyOnReset = true
    @AppStorage(SettingsKey.warningThreshold) private var warning = 80
    @AppStorage(SettingsKey.criticalThreshold) private var critical = 95

    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        Form {
            Section {
                Toggle("Send notifications", isOn: $notificationsEnabled)
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
                // The store sends nothing while notifications are off, reset alerts included.
                Toggle("Notify when limits reset", isOn: $notifyOnReset)
                    .disabled(!notificationsEnabled)
            }

            // Not disabled with notifications: these levels also set the usage colors.
            Section {
                ThresholdRow(title: "Warning at", value: warningBinding, range: warningRange)
                ThresholdRow(title: "Critical at", value: criticalBinding, range: criticalRange)
            } header: {
                Text("Usage levels")
            } footer: {
                Text("Usage turns orange at the warning level and red at the critical level. Notifications are sent at both.")
            }
        }
        .settingsPaneLayout()
        .task { notificationStatus = await notifier?.authorizationStatus() }
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

private struct ThresholdRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(value, format: .percent)
                    .monospacedDigit()
                Stepper(title, value: $value, in: range, step: 5)
                    .labelsHidden()
            }
        }
    }
}
