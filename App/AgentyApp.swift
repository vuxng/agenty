import SwiftUI

@main
struct AgentyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(store: model.store, onRetryKeychain: model.retryKeychainAccess, updater: model.updater)
        } label: {
            MenuBarLabel(store: model.store)
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
