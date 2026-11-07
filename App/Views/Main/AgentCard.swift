import SwiftUI
import UsageCore

struct AgentCard: View {
    let agent: AgentDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(verbatim: agent.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if agent.readError == nil {
                    modelBadge
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.fill.secondary, in: .capsule)
                }
            }
            description
                .font(.caption)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var modelBadge: some View {
        if let model = agent.model, model != "inherit" {
            Text(verbatim: model)
        } else {
            Text("Session model")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var description: some View {
        if let error = agent.readError {
            switch error {
            case .notText:
                Text("This file isn't plain text.")
                    .foregroundStyle(.orange)
            case .failed(let reason):
                Text(verbatim: reason)
                    .foregroundStyle(.orange)
            }
        } else if let description = agent.description, !description.isEmpty {
            Text(verbatim: description)
                .foregroundStyle(.secondary)
        } else {
            Text("No description")
                .foregroundStyle(.tertiary)
        }
    }
}
