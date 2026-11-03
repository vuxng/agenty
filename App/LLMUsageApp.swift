import SwiftUI

@main
struct LLMUsageApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(store: model.store)
        } label: {
            MenuBarLabel(store: model.store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
