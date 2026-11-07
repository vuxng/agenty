import AppKit
import Combine
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let instructionsSaveFailed = PassthroughSubject<Void, Never>()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.instructions.values.contains(where: \.isDirty)
                || model.configs.values.contains(where: \.isDirty) else { return .terminateNow }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Save changes before quitting?")
        alert.informativeText = String(localized: "Your unsaved changes will be lost if you discard them.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Discard"))
        alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
        sender.activate()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let dirtyDocuments = ProviderID.allCases.compactMap { model.instructions[$0] }.filter(\.isDirty)
            // Attempt every dirty document, even if an earlier one fails.
            for document in dirtyDocuments { document.save() }
            if let failed = dirtyDocuments.first(where: {
                $0.saveError != nil || $0.hasConflict || $0.loadError != nil || $0.isDirty
            }) {
                model.selectedProvider = failed.file.provider
                UserDefaults.standard.set(AppPage.instructions.rawValue, forKey: SettingsKey.mainPage)
                instructionsSaveFailed.send()
                return .terminateCancel
            }
            let dirtyConfigs = ProviderID.allCases.compactMap { model.configs[$0] }.filter(\.isDirty)
            guard !dirtyConfigs.isEmpty else { return .terminateNow }

            Task {
                var shouldTerminate = false
                defer { NSApp.reply(toApplicationShouldTerminate: shouldTerminate) }

                for document in dirtyConfigs {
                    if !document.dangerousEdits.isEmpty {
                        showConfigAfterCancelledQuit(document, confirmRiskySave: true)
                        return
                    }
                    await document.save()
                    if document.saveError != nil || document.hasConflict || document.isDirty {
                        showConfigAfterCancelledQuit(document, confirmRiskySave: false)
                        return
                    }
                }
                shouldTerminate = true
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    private func showConfigAfterCancelledQuit(_ document: ConfigDocument, confirmRiskySave: Bool) {
        let provider = document.backend.provider
        model.selectedProvider = provider
        UserDefaults.standard.set(AppPage.config.rawValue, forKey: SettingsKey.mainPage)
        model.pendingRiskySave = confirmRiskySave ? provider : nil
        // Reuse the installed view's window-opening path, including when the window is closed.
        instructionsSaveFailed.send()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
