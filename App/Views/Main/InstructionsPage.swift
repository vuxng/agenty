import AppKit
import SwiftUI
import UsageCore

@MainActor
struct InstructionsPage: View {
    let model: AppModel

    @FocusState private var editorIsFocused: Bool

    var body: some View {
        Group {
            if let document = model.instructions[model.selectedInstructions] {
                manuscript(document)
            }
        }
        .onAppear { refresh() }
        .onChange(of: model.selectedInstructions) {
            editorIsFocused = false
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func manuscript(_ document: InstructionsDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                providerSelector
                Text(verbatim: document.file.fileName)
                    .font(.system(size: 52, weight: .thin, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                Text(verbatim: document.file.displayPath)
                    .font(.caption.monospaced())
                Button("Show in Finder", systemImage: "folder") {
                    showInFinder(document.file.url)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show in Finder")
                Text(verbatim: "·")
                Text("Applies to new sessions").font(.caption)
            }
            .foregroundStyle(.secondary)

            if document.file.provider == .codex && document.isOverridden {
                Label("Codex is using AGENTS.override.md, so it ignores this file.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let loadError = document.loadError {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "doc.badge.ellipsis")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    if case .readFailed(let reason) = loadError {
                        Text("Agenty can't read this file: \(reason)")
                    } else {
                        Text("This file isn't plain text, so Agenty can't edit it.")
                    }
                    Button("Show in Finder") { showInFinder(document.file.url) }
                }
                .padding(.top, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                editor(document)
            }
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 16) {
            if document.hasConflict || document.saveError != nil || document.isDirty {
                SaveCapsule(document: document)
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
    }

    private var providerSelector: some View {
        HStack(spacing: 4) {
            ForEach(ProviderID.allCases, id: \.self) { provider in
                let selected = model.selectedInstructions == provider
                Button { model.selectedInstructions = provider } label: {
                    HStack(spacing: 8) {
                        ProviderStyle.brandLogo(provider)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                        Text(verbatim: provider.displayName)
                            .font(.callout.weight(selected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(selected
                                ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear), in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    private func editor(_ document: InstructionsDocument) -> some View {
        @Bindable var document = document
        return InstructionsEditor(text: $document.draft, tint: ProviderStyle.tint(document.file.provider))
            .id(document.file.provider)
            .focused($editorIsFocused)
            .overlay {
                if !document.fileExists && document.draft.isEmpty && !editorIsFocused {
                    // The same native editor and font keep the hint at the text's actual
                    // inset. Hide it on focus so it never overlaps the insertion point.
                    TextEditor(text: .constant(missingFileHint))
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .disabled(true)
                        .focusable(false)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint(document.fileExists ? Text(verbatim: "") : Text("This file doesn't exist yet. Agenty creates it when you save."))
            .padding(.horizontal, -4)
    }

    private var missingFileHint: AttributedString {
        var hint = AttributedString(String(localized: "This file doesn't exist yet. Agenty creates it when you save."))
        hint.font = .system(size: 13, design: .monospaced)
        hint.foregroundColor = Color(nsColor: .tertiaryLabelColor)
        return hint
    }

    private func refresh() {
        model.instructions[model.selectedInstructions]?.refresh()
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
