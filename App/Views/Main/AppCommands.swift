import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    @AppStorage(SettingsKey.mainPage) private var page = AppPage.usage

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                switch page {
                case .instructions:
                    model.instructions[model.selectedProvider]?.save()
                case .config:
                    model.requestConfigSave()
                case .usage, .agents:
                    break
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!canSave)
        }

        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                Task { await model.store.refreshAll(force: true) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(page != .usage)
        }
    }

    private var canSave: Bool {
        switch page {
        case .instructions: model.instructions[model.selectedProvider]?.isDirty == true
        case .config: model.configs[model.selectedProvider]?.isDirty == true
        case .usage, .agents: false
        }
    }
}
