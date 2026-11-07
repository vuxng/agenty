import SwiftUI
import UsageCore

struct ConfigModelCard: View {
    let document: ConfigDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Model").font(.title3.weight(.semibold))
            if let config = document.config {
                ForEach(config.efforts, id: \.path) { setting in
                    effort(setting, hasModelSettings: config.efforts.contains { $0.modelName != nil })
                }
                if let fast = config.fast, document.isFastAvailable {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Fast")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("Fast", isOn: Binding(
                                get: { document.value(at: fast.path) == fast.onValue },
                                set: { document.set($0 ? fast.onValue : nil, at: fast.path) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        .disabled(fast.lockedValue != nil)
                        if let locked = fast.lockedValue {
                            Text("Set to \(locked). Change it in File mode.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let description = document.currentModel?.fastDescription {
                            Text(verbatim: description)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
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

    private func effort(_ setting: EffortSetting, hasModelSettings: Bool) -> some View {
        let levels = document.levels(for: setting)
        let title = setting.modelName ?? (hasModelSettings
            ? String(localized: "Other models") : String(localized: "Reasoning effort"))
        let selection = Binding<Double>(
            get: {
                guard case .string(let level) = document.value(at: setting.path),
                      let index = levels.firstIndex(of: level) else { return 0 }
                return Double(index + 1)
            },
            set: { value in
                let index = Int(value.rounded())
                guard index >= 0, index <= levels.count else { return }
                document.set(index == 0 ? nil : .string(levels[index - 1]), at: setting.path)
            }
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title).font(.headline)
            Slider(value: selection, in: 0...Double(max(1, levels.count)), step: 1) {
                Text(verbatim: title)
            } tick: { value in
                let index = Int(value)
                if index == 0 {
                    return SliderTick("Default", value)
                }
                guard index <= levels.count else { return nil }
                return SliderTick(value) { Text(verbatim: levels[index - 1]) }
            }
            .labelsHidden()
            .disabled(levels.isEmpty)
            .accessibilityValue(Text(verbatim: selection.wrappedValue == 0
                ? String(localized: "Default") : levels[Int(selection.wrappedValue) - 1]))
        }
    }
}
