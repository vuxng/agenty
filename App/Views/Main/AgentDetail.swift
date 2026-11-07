import SwiftUI
import UsageCore

@MainActor
struct AgentDetail: View {
    let agent: AgentDefinition
    let provider: ProviderID
    let path: String
    let backTitle: String
    let onBack: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: agent.name, path: path, revealURL: agent.url) {
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .frame(width: 16, height: 16)
                        Text(verbatim: backTitle)
                            .font(.callout)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .padding(4)
                .glassEffect(.regular, in: .capsule)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Back to agents")
            } trailing: {}

            if let error = agent.readError {
                PageMessage(systemImage: "doc.badge.ellipsis", text: readErrorText(error)) {
                    Button("Show in Finder") { Finder.show(agent.url) }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if agent.isLineScanned {
                            Label("This file isn't valid YAML, so Agenty read it line by line.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(.orange)
                        }
                        if let description = agent.description, !description.isEmpty {
                            Text(verbatim: description)
                                .font(.body)
                        }
                        fieldCard
                        ForEach(blockFields) { field in
                            if case .block(let text) = field.value {
                                codeCard(name: field.key, text: text)
                            }
                        }
                        if let prompt = agent.prompt, !prompt.isEmpty {
                            Text(MarkdownStyler.styled(prompt, tint: ProviderStyle.tint(provider)))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // A line-scanned file can repeat a key. Keep every occurrence visible.
    private struct Field: Identifiable {
        struct ID: Hashable {
            let key: String
            let occurrence: Int
        }

        let id: ID
        let value: AgentFieldValue
        var key: String { id.key }
    }

    private var fields: [Field] {
        var occurrences: [String: Int] = [:]
        return agent.fields.map { field in
            let occurrence = occurrences[field.key, default: 0]
            occurrences[field.key] = occurrence + 1
            return Field(id: Field.ID(key: field.key, occurrence: occurrence), value: field.value)
        }
    }

    private var textFields: [Field] {
        fields.filter { if case .text = $0.value { true } else { false } }
    }

    private var blockFields: [Field] {
        fields.filter { if case .block = $0.value { true } else { false } }
    }

    private var fieldCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(verbatim: "model")
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                modelBadge
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.fill.secondary, in: .capsule)
            }
            ForEach(textFields) { field in
                if case .text(let text) = field.value {
                    Divider()
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: field.key)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(verbatim: text)
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder private var modelBadge: some View {
        if let model = agent.model, model != "inherit" {
            Text(verbatim: model)
        } else {
            Text("Session model")
                .foregroundStyle(.secondary)
        }
    }

    private func codeCard(name: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: name)
                .font(.title3.weight(.semibold))
            Text(verbatim: text)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private func readErrorText(_ error: AgentReadError) -> String {
        let reason: String
        switch error {
        case .notText:
            reason = String(localized: "This file isn't plain text.", locale: locale)
        case .failed(let message):
            reason = message
        }
        return String(localized: "Agenty can't read this file: \(reason)", locale: locale)
    }
}

#if DEBUG
@MainActor
private struct AgentDetailPreview: View {
    let agent: AgentDefinition

    var body: some View {
        let directory = PreviewAgentSource(provider: .claude, result: .success(PreviewAgentSource.claudeListing)).directory
        AgentDetail(agent: agent, provider: .claude, path: directory.displayPath(of: agent.url),
                    backTitle: String(localized: "\(6) agents"), onBack: {})
            .frame(width: 860, height: 580)
            .background { AmbientField(page: .agents, selected: .claude) }
    }
}

#Preview("Agent with only hooks") {
    AgentDetailPreview(agent: PreviewAgentSource.hooksAgent)
}

#Preview("Agent with fields and Markdown prompt") {
    AgentDetailPreview(agent: PreviewAgentSource.promptAgent)
}

#Preview("Line-scanned agent") {
    AgentDetailPreview(agent: PreviewAgentSource.lineScannedAgent)
}

#Preview("Unreadable agent") {
    AgentDetailPreview(agent: PreviewAgentSource.unreadableAgent)
}
#endif
