import SwiftUI
import UsageCore

struct ConfigChoiceCard: View {
    let document: ConfigDocument
    let choice: ConfigChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: ConfigText.title(choice.kind)).font(.title3.weight(.semibold))
            Picker(selection: Binding(
                get: { selection },
                set: { document.set($0, at: choice.path) }
            )) {
                ForEach(choice.options, id: \.self) { value in
                    HStack(spacing: 4) {
                        Text(verbatim: ConfigText.label(choice.kind, value))
                        if isDangerous(value) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .accessibilityLabel(Text("Warning"))
                        }
                    }
                    .foregroundStyle(isDangerous(value) ? Color.orange : Color.primary)
                    .help(ConfigText.description(choice.kind, value) ?? "")
                    .tag(value)
                }
            } label: {
                Text(verbatim: ConfigText.title(choice.kind))
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if let description = ConfigText.description(choice.kind, selection) {
                HStack(alignment: .top, spacing: 8) {
                    if isDangerous(selection) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: description)
                }
                .font(.callout)
                .foregroundStyle(isDangerous(selection) ? Color.orange : Color.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .disabled(document.isSaving)
    }

    private var selection: ConfigValue? {
        guard let value = document.value(at: choice.path),
              !choice.unsetAliases.contains(value) else { return nil }
        return value
    }

    private func isDangerous(_ value: ConfigValue?) -> Bool {
        value.map { choice.dangerous.contains($0) } ?? false
    }
}
