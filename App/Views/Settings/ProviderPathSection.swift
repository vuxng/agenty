import SwiftUI
import UsageCore

struct ProviderPathSection: View {
    let provider: ProviderID
    let locator: CLILocator

    @AppStorage private var path: String
    @State private var found: URL?
    @State private var isChecking = true

    init(provider: ProviderID, locator: CLILocator) {
        self.provider = provider
        self.locator = locator
        _path = AppStorage(wrappedValue: "", SettingsKey.providerPath(provider))
    }

    var body: some View {
        Section {
            HStack {
                TextField("\(provider.displayName) path", text: $path, prompt: Text("Auto-detect"))
                Button("Choose…") {
                    if let chosen = ExecutablePicker.choose() { path = chosen }
                }
            }
            .task(id: path) {
                isChecking = true
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
                let result = await locator.locate(provider.rawValue, override: path.isEmpty ? nil : path)
                if Task.isCancelled { return }
                found = result
                isChecking = false
            }
        } footer: {
            status
        }
    }

    @ViewBuilder private var status: some View {
        if isChecking {
            Label {
                Text("Checking…")
            } icon: {
                ProgressView().controlSize(.mini)
            }
        } else if let found {
            Label {
                Text("Found at \(found.path)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        } else {
            Label {
                Text("Not found")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
    }
}
