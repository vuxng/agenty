import SwiftUI
import UsageCore

struct MenuBarLabel: View {
    let store: UsageStore
    @AppStorage(SettingsKey.menuBarStyle) private var styleRaw = MenuBarStyle.bars.rawValue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let style = MenuBarStyle(rawValue: styleRaw) ?? .bars
        Image(nsImage: MenuBarRenderer.render(
            style: style,
            summaries: store.summaries,
            overall: store.overall,
            colorScheme: colorScheme
        ))
    }
}

// MARK: - Previews

/// Shows one style across normal / warning 84% / critical 97% / error.
struct MenuBarPreviewGrid: View {
    let style: MenuBarStyle
    @State private var stores: [PreviewEntry] = []

    struct PreviewEntry: Identifiable {
        let id: String
        let store: UsageStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(stores) { entry in
                HStack {
                    Text(entry.id).frame(width: 70, alignment: .leading)
                    Image(nsImage: MenuBarRenderer.render(
                        style: style,
                        summaries: entry.store.summaries,
                        overall: entry.store.overall,
                        colorScheme: .light))
                }
            }
        }
        .padding()
        .task { stores = await Self.makeStores() }
    }

    private static func makeStores() async -> [PreviewEntry] {
        func ok(_ p: Double) -> [ProviderID: Result<UsageSnapshot, UsageError>] {
            [.claude: .success(.preview(.claude, percent: p)),
             .codex: .success(.preview(.codex, percent: 30)),
             .grok: .success(.preview(.grok, percent: 12))]
        }
        var error = ok(40)
        error[.codex] = .failure(.notLoggedIn)
        return [
            PreviewEntry(id: "Normal", store: await previewStore(ok(40))),
            PreviewEntry(id: "Warning", store: await previewStore(ok(84))),
            PreviewEntry(id: "Critical", store: await previewStore(ok(97))),
            PreviewEntry(id: "Error", store: await previewStore(error)),
        ]
    }
}
