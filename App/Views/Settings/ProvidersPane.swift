import SwiftUI
import UsageCore

struct ProvidersPane: View {
    let providers: [ProviderID]
    let locator: CLILocator

    var body: some View {
        Form {
            Section {
                ForEach(providers, id: \.self) { ProviderToggle(provider: $0) }
            }
            if providers.contains(.codex) {
                ProviderPathSection(provider: .codex, locator: locator)
            }
        }
        .settingsPaneLayout()
    }
}

private struct ProviderToggle: View {
    let provider: ProviderID
    @AppStorage private var enabled: Bool

    init(provider: ProviderID) {
        self.provider = provider
        _enabled = AppStorage(wrappedValue: true, SettingsKey.providerEnabled(provider))
    }

    var body: some View {
        Toggle(isOn: $enabled) {
            Label {
                Text(provider.displayName)
            } icon: {
                ProviderStyle.brandLogo(provider)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true) // the provider name follows
            }
        }
    }
}
