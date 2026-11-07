import AppKit
import SwiftUI
import UsageCore

@MainActor
struct AgentsPage: View {
    let model: AppModel

    @State private var openURL: URL?

    var body: some View {
        @Bindable var model = model
        Group {
            if let document = model.agents[model.selectedProvider] {
                AgentsPageContent(document: document, selection: $model.selectedProvider,
                                  onOpen: { openURL = $0 }, onChoosePath: {
                    guard let path = ExecutablePicker.choose() else { return }
                    UserDefaults.standard.set(path, forKey: SettingsKey.providerPath(.codex))
                    Task { await document.refresh() }
                })
            }
        }
        .task(id: model.selectedProvider) {
            await model.agents[model.selectedProvider]?.refresh()
        }
        .onChange(of: model.selectedProvider) { openURL = nil }
        .onDisappear { openURL = nil }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard let document = model.agents[model.selectedProvider] else { return }
            Task { await document.refresh() }
        }
    }
}

@MainActor
private struct AgentsPageContent: View {
    let document: AgentsDocument
    @Binding var selection: ProviderID
    let onOpen: (URL) -> Void
    let onChoosePath: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: title, path: directory.displayPath(of: directory.url),
                       revealURL: document.listing?.folderExists == true ? directory.url : nil) {
                ProviderSelector(selection: $selection, providers: ProviderID.allCases)
            } trailing: {}

            if document.listing?.usesClaudeAgents == true {
                Label("Grok also uses the agents in ~/.claude/agents.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            content
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var directory: AgentDirectory { document.source.directory }

    private var title: String {
        if let listing = document.listing {
            String(localized: "\(listing.agents.count) agents", locale: locale)
        } else {
            String(localized: "Agents", locale: locale)
        }
    }

    @ViewBuilder private var content: some View {
        if let error = document.loadError {
            switch error {
            case .cliNotFound:
                PageMessage(systemImage: "exclamationmark.triangle",
                            text: String(localized: "Agenty needs the Codex CLI to read Codex agents.", locale: locale)) {
                    Button("Choose path…", action: onChoosePath)
                }
            case .failed(let reason):
                PageMessage(systemImage: "exclamationmark.triangle",
                            text: String(localized: "Agenty can't read the \(document.source.provider.displayName) agents: \(reason)", locale: locale)) {
                    Button("Try Again") { Task { await document.refresh() } }
                }
            }
        } else if document.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if let listing = document.listing {
            if !listing.folderExists {
                PageMessage(systemImage: "doc.badge.ellipsis",
                            text: String(localized: "This folder doesn't exist yet, so \(document.source.provider.displayName) has no agents of yours.", locale: locale)) {}
            } else if listing.agents.isEmpty {
                PageMessage(systemImage: "doc.badge.ellipsis",
                            text: String(localized: "\(document.source.provider.displayName) has no agents of yours in this folder.", locale: locale)) {}
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(listing.agents) { agent in
                            Button { onOpen(agent.url) } label: {
                                AgentCard(agent: agent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
@MainActor
private struct AgentsPagePreview: View {
    let provider: ProviderID
    let result: Result<AgentListing, AgentLoadError>

    @State private var document: AgentsDocument?

    var body: some View {
        Group {
            if let document {
                AgentsPageContent(document: document, selection: .constant(provider),
                                  onOpen: { _ in }, onChoosePath: {})
            } else {
                ProgressView()
            }
        }
        .frame(width: 860, height: 580)
        .background { AmbientField(page: .agents, selected: provider) }
        .task {
            let source = PreviewAgentSource(provider: provider, result: result)
            let document = AgentsDocument(source: source)
            self.document = document
            await document.refresh()
        }
    }
}

#Preview("Six Claude agents") {
    AgentsPagePreview(provider: .claude, result: .success(PreviewAgentSource.claudeListing))
}

#Preview("Missing agents folder") {
    AgentsPagePreview(provider: .claude, result: .success(AgentListing(folderExists: false, agents: [])))
}

#Preview("Codex CLI not found") {
    AgentsPagePreview(provider: .codex, result: .failure(.cliNotFound))
}

#Preview("Grok also uses Claude agents") {
    AgentsPagePreview(provider: .grok, result: .success(AgentListing(folderExists: true, agents: [], usesClaudeAgents: true)))
}
#endif
