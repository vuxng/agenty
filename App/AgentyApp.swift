import SwiftUI

@main
struct AgentyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var model: AppModel { delegate.model }

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(store: model.store, onRetryKeychain: model.retryKeychainAccess, updater: model.updater)
        } label: {
            AppMenuBarLabel(delegate: delegate)
        }
        .menuBarExtraStyle(.window)

        Window("Agenty", id: "main") {
            MainWindow(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 980, height: 640)
        .defaultLaunchBehavior(.suppressed)
        .commands { AppCommands(model: model) }

        Settings {
            SettingsView(model: model)
        }
    }
}

private struct AppMenuBarLabel: View {
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarLabel(store: delegate.model.store)
            .onReceive(delegate.instructionsSaveFailed) { _ in
                // Open from an installed view's environment, after the delegate
                // has returned terminateCancel (including with no window open).
                Task { @MainActor in
                    openWindow(id: "main")
                    NSApp.activate()
                }
            }
    }
}
