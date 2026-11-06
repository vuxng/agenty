import SwiftUI
import UsageCore

struct ConfigHero: View {
    let document: ConfigDocument

    @State private var showingCustomModel = false
    @State private var customModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model").font(.headline).foregroundStyle(.secondary)
            Menu {
                Button("Default") { document.selectModel(nil) }
                if let setting = document.config?.model {
                    ForEach(setting.options) { option in
                        Button { document.selectModel(option.id) } label: {
                            Text(verbatim: option.displayName)
                        }
                    }
                    if setting.allowsCustom {
                        Divider()
                        Button("Other…") {
                            if case .string(let value) = document.value(at: setting.path) {
                                customModel = value
                            } else {
                                customModel = ""
                            }
                            showingCustomModel = true
                        }
                    }
                }
            } label: {
                Text(verbatim: modelName)
                    .font(.system(size: 52, weight: .thin, design: .rounded))
                    .multilineTextAlignment(.leading)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(document.config == nil || document.isSaving)
            .accessibilityLabel(Text("Model"))
            .accessibilityValue(Text(verbatim: modelName))

            HStack(spacing: 8) {
                Text(verbatim: document.backend.displayPath)
                    .font(.caption.monospaced())
                Button("Show in Finder", systemImage: "folder") {
                    Finder.show(document.backend.file.url)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show in Finder")
                Text(verbatim: "·")
                Text("Applies to new sessions").font(.caption)
            }
            .foregroundStyle(.secondary)

            if let notice = document.notice {
                switch notice {
                case .effortReset:
                    Label("Reasoning effort went back to Default because this model doesn't support that level.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                case .overridden(let message):
                    Label { Text(verbatim: message) } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.callout)
                    .foregroundStyle(.orange)
                case .fileNotChecked:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Other…", isPresented: $showingCustomModel) {
            TextField("Model ID", text: $customModel)
            Button("Cancel", role: .cancel) {}
            Button("Apply") { document.selectModel(customModel.trimmingCharacters(in: .whitespacesAndNewlines)) }
                .disabled(customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var modelName: String {
        guard let setting = document.config?.model,
              let value = document.value(at: setting.path) else { return String(localized: "Default") }
        switch value {
        case .string(let id): return document.currentModel?.displayName ?? id
        case .opaque: return String(localized: "Custom")
        case .bool(let value): return String(value)
        }
    }
}
