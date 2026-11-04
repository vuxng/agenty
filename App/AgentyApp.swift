import SwiftUI

@main
struct AgentyApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(store: model.store, onRetryKeychain: model.retryKeychainAccess)
        } label: {
            MenuBarLabel(store: model.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
