import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    @AppStorage(SettingsKey.mainPage) private var page = AppPage.usage

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                Task { await model.store.refreshAll(force: true) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(page != .usage)
        }
    }
}
