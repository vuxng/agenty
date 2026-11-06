import SwiftUI
import UsageCore

struct ConfigPluginCard: View {
    let document: ConfigDocument

    @State private var search = ""
    @State private var showingAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Plugins").font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let config = document.config {
                    Text("\(config.plugins.filter(isEnabled).count) of \(config.plugins.count) on")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if let config = document.config {
                TextField("Search plugins", text: $search)
                    .textFieldStyle(.roundedBorder)
                let filtered = config.plugins.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
                ForEach(showingAll ? filtered : Array(filtered.prefix(8))) { plugin in
                    if let path = plugin.path {
                        Toggle(isOn: Binding(
                            get: { isEnabled(plugin) },
                            set: { document.set(.bool($0), at: path) }
                        )) {
                            Text(verbatim: plugin.name)
                        }
                        .toggleStyle(.switch)
                    } else {
                        HStack(spacing: 8) {
                            Text(verbatim: plugin.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Synced").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .opacity(0.55)
                    }
                }
                if !showingAll, filtered.count > 8 {
                    Button("Show all \(filtered.count)") { showingAll = true }
                        .buttonStyle(.borderless)
                }
                if !config.pluginsComplete {
                    Label {
                        if document.backend.provider == .claude {
                            Text("Plugins from claude.ai are missing because Agenty can't find the Claude CLI.")
                        } else {
                            Text("Some plugins couldn't be loaded.")
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .disabled(document.isSaving)
    }

    private func isEnabled(_ plugin: PluginItem) -> Bool {
        guard let path = plugin.path else { return plugin.isEnabled }
        if case .bool(let enabled) = document.value(at: path) { return enabled }
        return plugin.isEnabled
    }
}
