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
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
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
        .confirmationDialog("Save changes before switching modes?", isPresented: $showingModeDialog,
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

    @ViewBuilder
    private func controls(_ document: ConfigDocument) -> some View {
        if document.isLoading {
            ProgressView()
        } else if let error = document.loadError {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(verbatim: error.failureReason)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                if error == .cliNotFound {
                    Button("Choose path…") {
                        guard let path = ExecutablePicker.choose() else { return }
                        UserDefaults.standard.set(path, forKey: SettingsKey.providerPath(.codex))
                        Task { await document.refresh(force: true) }
                    }
                }
                Button("Open File") { requestMode(.file, document: document) }
            }
            .padding(.top, 24)
        } else {
            Color.clear
        }
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
                    showInFinder(document.backend.file.url)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show in Finder")
                Text(verbatim: "·")
                Text("Applies to new sessions").font(.caption)
            }
            .foregroundStyle(.secondary)

            if document.loadError == .cliNotFound || document.notice == .fileNotChecked {
                Label("This file hasn't been checked.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let notice = document.notice {
                switch notice {
                case .effortReset:
                    Text("Effort was reset for the selected model.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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

    private func showInFinder(_ url: URL) {
        let manager = FileManager.default
        if manager.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let parent = url.deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue {
                NSWorkspace.shared.open(parent)
            }
        }
    }
}
