import SwiftUI
import UsageCore

struct ProviderPathRow: View {
    let provider: ProviderID
    let locator: CLILocator

    @AppStorage private var path: String
    @State private var found: URL?
    @State private var isChecking = false

    init(provider: ProviderID, locator: CLILocator) {
        self.provider = provider
        self.locator = locator
        _path = AppStorage(wrappedValue: "", SettingsKey.providerPath(provider))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("\(provider.displayName) path", text: $path, prompt: Text("Auto-detect"))
                Button("Choose…") {
                    if let chosen = ExecutablePicker.choose() { path = chosen }
                }
            }
            HStack(spacing: 4) {
                if isChecking {
                    ProgressView().controlSize(.small)
                } else if let found {
                    Text("✓ Found at \(found.path)").foregroundStyle(.secondary)
                } else {
                    Text("✗ Not found").foregroundStyle(.red)
                }
            }
            .font(.caption)
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
    }
}
