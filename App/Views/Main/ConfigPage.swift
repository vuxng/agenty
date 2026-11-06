import AppKit
import SwiftUI
import UsageCore

@MainActor
struct ConfigPage: View {
    let model: AppModel

    @State private var pendingMode: ConfigMode?
    @State private var pendingProvider: ProviderID?
    @State private var showingModeDialog = false
    @State private var awaitingModeSave = false

    var body: some View {
        Group {
            if let document = model.configs[model.selectedProvider] {
                content(document)
            }
        }
        .onAppear { refresh(force: true) }
        .onChange(of: model.selectedProvider) {
            cancelModeChange()
            showingModeDialog = false
            model.pendingRiskySave = nil
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .confirmationDialog("Save a risky setting?", isPresented: Binding(
            get: { model.pendingRiskySave != nil },
            set: { if !$0 { model.pendingRiskySave = nil } }
        ), titleVisibility: .visible, presenting: riskyDocument) { document in
            Button("Save Anyway", role: .destructive) {
                model.pendingRiskySave = nil
                Task { await document.save() }
            }
            Button("Cancel", role: .cancel) {
                model.pendingRiskySave = nil
                cancelModeChange()
            }
            .keyboardShortcut(.defaultAction)
        } message: { document in
            Text("The agent could run commands without asking: \(riskyValues(document))")
        }
    }

    private func content(_ document: ConfigDocument) -> some View {
        VStack(spacing: 16) {
            header(document)
            switch document.mode {
            case .controls:
                controls(document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .file:
                file(document)
            }
        }
        .frame(maxWidth: 960)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 16) {
            if document.hasConflict || document.saveError != nil || document.isDirty {
                SaveCapsule(document: document, onSave: model.requestConfigSave)
                    .disabled(document.isSaving || document.isLoading)
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .confirmationDialog("Save changes before switching?", isPresented: $showingModeDialog,
                            titleVisibility: .visible) {
            Button("Save") {
                awaitingModeSave = true
                model.requestConfigSave()
            }
            Button("Discard", role: .destructive) {
                document.revert()
                if let pendingMode { _ = document.switchMode(to: pendingMode) }
                cancelModeChange()
            }
            Button("Cancel", role: .cancel) { cancelModeChange() }
        } message: {
            Text("Your unsaved config changes will be lost if you discard them.")
        }
        .onChange(of: document.isDirty) { finishModeChange(document) }
        .onChange(of: document.isSaving) { finishModeChange(document) }
    }

    private func header(_ document: ConfigDocument) -> some View {
        @Bindable var model = model
        return HStack(spacing: 16) {
            ProviderSelector(selection: $model.selectedProvider)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Config mode", selection: Binding(
                get: { document.mode },
                set: { requestMode($0, document: document) }
            )) {
                Text("Controls").tag(ConfigMode.controls)
                Text("File").tag(ConfigMode.file)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
            .glassEffect(.regular, in: .capsule)
            .disabled(document.isSaving)
        }
    }

    private func controls(_ document: ConfigDocument) -> some View {
        ConfigControlsContent(document: document, onOpenFile: {
            requestMode(.file, document: document)
        }, onChoosePath: {
            guard let path = ExecutablePicker.choose() else { return }
            UserDefaults.standard.set(path, forKey: SettingsKey.providerPath(.codex))
            Task { await document.refresh(force: true) }
        })
        .id(document.backend.provider)
    }

    private func file(_ document: ConfigDocument) -> some View {
        @Bindable var document = document
        return VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: document.backend.file.url.lastPathComponent)
                .font(.system(size: 52, weight: .thin, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
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

            if document.loadError == .cliNotFound || document.notice == .fileNotChecked {
                Label("Agenty can't check this file because it can't find the Codex CLI.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let notice = document.notice {
                switch notice {
                case .effortReset:
                    Label("Reasoning effort went back to Default because this model doesn't support that level.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                case .overridden(let message):
                    Label("Another config overrides these settings: \(message)",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                case .fileNotChecked:
                    EmptyView()
                }
            }
            if let error = document.loadError, error != .cliNotFound {
                Text(verbatim: error.failureReason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ConfigFileEditor(text: $document.fileDraft)
                .id(document.backend.provider)
                .accessibilityLabel("Config file")
                .disabled(document.isLoading || document.isSaving)
        }
        .frame(maxWidth: 720)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func requestMode(_ mode: ConfigMode, document: ConfigDocument) {
        guard mode != document.mode else { return }
        if !document.switchMode(to: mode) {
            pendingMode = mode
            pendingProvider = document.backend.provider
            showingModeDialog = true
        }
    }

    private func finishModeChange(_ document: ConfigDocument) {
        guard awaitingModeSave, !document.isSaving,
              pendingProvider == document.backend.provider,
              pendingProvider == model.selectedProvider else { return }
        guard document.saveError == nil, !document.hasConflict else {
            cancelModeChange()
            return
        }
        guard !document.isDirty, let pendingMode else { return }
        _ = document.switchMode(to: pendingMode)
        cancelModeChange()
    }

    private func cancelModeChange() {
        pendingMode = nil
        pendingProvider = nil
        awaitingModeSave = false
    }

    private func refresh(force: Bool = false) {
        guard let document = model.configs[model.selectedProvider] else { return }
        Task { await document.refresh(force: force) }
    }

    private var riskyDocument: ConfigDocument? {
        guard let provider = model.pendingRiskySave else { return nil }
        return model.configs[provider]
    }

    private func riskyValues(_ document: ConfigDocument) -> String {
        document.dangerousEdits.compactMap { edit in
            switch edit.value {
            case .string(let value), .opaque(let value): return value
            case .bool(let value): return String(value)
            case nil: return nil
            }
        }.joined(separator: ", ")
    }
}

private struct ConfigControlsContent: View {
    let document: ConfigDocument
    let onOpenFile: () -> Void
    let onChoosePath: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ConfigHero(document: document)
                if let error = document.loadError {
                    VStack(alignment: .leading, spacing: 12) {
                        Label {
                            if error == .unsupportedCLI {
                                Text("This version of Codex doesn't support editing settings yet.")
                            } else {
                                Text(verbatim: error.failureReason)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        if error == .cliNotFound {
                            Button("Choose path…", action: onChoosePath)
                        }
                        Button("Open File", action: onOpenFile)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 16) {
                            ConfigModelCard(document: document)
                            if let config = document.config {
                                ForEach(config.choices, id: \.path) { choice in
                                    ConfigChoiceCard(document: document, choice: choice)
                                }
                            } else {
                                loadingCard(document.backend.provider == .claude ? .claudePermission : .codexSandbox)
                                loadingCard(document.backend.provider == .claude ? .claudeSandbox : .codexApproval)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: 16) {
                            ConfigPluginCard(document: document)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func loadingCard(_ kind: ConfigChoiceKind) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: ConfigText.title(kind)).font(.title3.weight(.semibold))
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

#if DEBUG
private actor ConfigPreviewBackend: ConfigBackend {
    let provider: ProviderID
    let file: TextFile
    private var config: AgentConfig
    private let error: ConfigError?
    private let loading: Bool
    private let warning: Bool

    init(provider: ProviderID, error: ConfigError?, loading: Bool, warning: Bool) {
        self.provider = provider
        self.error = error
        self.loading = loading
        self.warning = warning
        self.file = TextFile(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("Agenty-ConfigPreview-\(UUID().uuidString)")
            .appendingPathComponent(provider == .claude ? "settings.json" : "config.toml"))
        self.config = Self.sample(provider)
    }

    func load() async throws(ConfigError) -> ConfigSnapshot {
        if loading { try? await Task.sleep(for: .seconds(3600)) }
        if let error { throw error }
        return ConfigSnapshot(config: config, version: nil)
    }

    func save(_ edits: [ConfigEdit], version: String?) async throws(ConfigError) -> ConfigSaveResult {
        for edit in edits { config.values[edit.path] = edit.value }
        return ConfigSaveResult(overrideMessage: warning
            ? String(localized: "Your organization overrides these settings.") : nil)
    }

    func validate(_ text: String) async throws(ConfigError) -> ConfigValidation { .valid }

    func writeFile(_ text: String) async throws(ConfigError) {
        do { try file.write(text) }
        catch { throw .writeFailed(String(describing: error)) }
    }

    private static func sample(_ provider: ProviderID) -> AgentConfig {
        let claude = provider == .claude
        let levels = ["low", "medium", "high", "xhigh"]
        let models: [ModelOption] = claude
            ? ["best", "fable", "opus", "sonnet", "haiku", "opus[1m]", "sonnet[1m]", "opusplan"].map {
                ModelOption(id: $0, displayName: $0, isDefault: $0 == "best", efforts: levels, fastDescription: nil)
            }
            : [
                ModelOption(id: "gpt-5.4", displayName: "GPT-5.4", isDefault: true, efforts: levels,
                            fastDescription: String(localized: "Faster responses with priority processing.")),
                ModelOption(id: "gpt-5.4-mini", displayName: "GPT-5.4 mini", isDefault: false,
                            efforts: ["low", "medium"], fastDescription: nil),
            ]
        let efforts: [EffortSetting] = claude
            ? [EffortSetting(path: ["modelSettings", "opus", "effortLevel"], modelName: "opus", levels: levels),
               EffortSetting(path: ["effortLevel"], modelName: nil, levels: levels)]
            : [EffortSetting(path: ["model_reasoning_effort"], modelName: nil, levels: nil)]
        let choices: [ConfigChoice] = claude ? [
            ConfigChoice(kind: .claudePermission, path: ["permissions", "defaultMode"],
                         options: [.string("dontAsk"), .string("plan"), nil, .string("acceptEdits"),
                                   .string("auto"), .string("bypassPermissions")],
                         dangerous: [.string("bypassPermissions")],
                         unsetAliases: [.string("default"), .string("manual")]),
            ConfigChoice(kind: .claudeSandbox, path: ["sandbox", "enabled"],
                         options: [nil, .bool(true), .bool(false)], dangerous: [], unsetAliases: []),
        ] : [
            ConfigChoice(kind: .codexSandbox, path: ["sandbox_mode"],
                         options: [nil, .string("read-only"), .string("workspace-write"), .string("danger-full-access")],
                         dangerous: [.string("danger-full-access")], unsetAliases: []),
            ConfigChoice(kind: .codexApproval, path: ["approval_policy"],
                         options: [nil, .string("untrusted"), .string("on-request"), .string("never")],
                         dangerous: [.string("never")], unsetAliases: []),
        ]
        let plugins = ["GitHub", "Linear", "Figma", "Notion", "Slack", "Sentry", "Vercel", "Neon", "Playwright", "Xcode"]
            .enumerated().map { index, name in
                let id = "\(name.lowercased())@preview"
                return PluginItem(id: id, name: name,
                                  path: claude && index == 2 ? nil
                                    : (claude ? ["enabledPlugins", id] : ["plugins", id, "enabled"]),
                                  isEnabled: index < 5)
            }
        var values: [ConfigPath: ConfigValue] = [["model"]: .string(claude ? "opus" : "gpt-5.4")]
        values[efforts[0].path] = .string("high")
        values[choices[0].path] = .string(claude ? "manual" : "workspace-write")
        if !claude { values[["approval_policy"]] = .string("on-request") }
        for plugin in plugins {
            if let path = plugin.path { values[path] = .bool(plugin.isEnabled) }
        }
        return AgentConfig(
            model: ModelSetting(path: ["model"], options: models, allowsCustom: claude),
            efforts: efforts,
            fast: FastSetting(path: claude ? ["fastMode"] : ["service_tier"],
                              onValue: claude ? .bool(true) : .string("priority"),
                              lockedValue: nil, requiresModelTier: !claude),
            choices: choices, plugins: plugins, pluginsComplete: true, values: values
        )
    }
}

private struct ConfigPagePreview: View {
    var provider: ProviderID = .claude
    var error: ConfigError?
    var loading = false
    var warning = false

    @State private var document: ConfigDocument?

    var body: some View {
        Group {
            if let document {
                VStack(spacing: 16) {
                    if document.mode == .controls {
                        ConfigControlsContent(document: document, onOpenFile: {
                            _ = document.switchMode(to: .file)
                        }, onChoosePath: {})
                    } else {
                        @Bindable var document = document
                        ConfigFileEditor(text: $document.fileDraft)
                    }
                }
                .frame(maxWidth: 960)
                .padding(24)
            } else {
                ProgressView()
            }
        }
        .frame(width: 960, height: 720)
        .background { AmbientField(page: .config, selected: provider) }
        .task {
            let backend = ConfigPreviewBackend(provider: provider, error: error, loading: loading, warning: warning)
            defer { try? FileManager.default.removeItem(at: backend.file.url.deletingLastPathComponent()) }
            let preview = ConfigDocument(backend: backend)
            document = preview
            await preview.refresh(force: true)
            if warning { await preview.save() }
        }
    }
}

#Preview("Config — Claude") { ConfigPagePreview() }
#Preview("Config — Codex") { ConfigPagePreview(provider: .codex) }
#Preview("Config — Loading") { ConfigPagePreview(loading: true) }
#Preview("Config — Invalid file") {
    ConfigPagePreview(error: .invalidFile(String(localized: "Expected a closing brace.")))
}
#Preview("Config — Missing CLI") { ConfigPagePreview(provider: .codex, error: .cliNotFound) }
#Preview("Config — Organization override") { ConfigPagePreview(provider: .codex, warning: true) }
#endif
