import SwiftUI
import UsageCore

@MainActor
struct InstructionsEditor: View {
    @Binding var text: String
    let tint: Color

    @State private var attributed: AttributedString
    @State private var selection = AttributedTextSelection()

    init(text: Binding<String>, tint: Color) {
        self._text = text
        self.tint = tint
        // Seed the editing buffer once; later draft changes are synchronized below.
        var initial = AttributedString(text.wrappedValue)
        Self.applyStyling(to: &initial, tint: tint)
        self.attributed = initial
    }

    var body: some View {
        TextEditor(text: editorText, selection: $selection)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .accessibilityLabel("Instructions Markdown")
            .onChange(of: attributed) { restyle() }
            .onChange(of: tint) { restyle() }
            .onChange(of: text) { _, newText in
                // An editor-originated update is already in the buffer.
                guard String(attributed.characters) != newText else { return }
                var updated = attributed
                var updatedSelection = selection
                updated.transform(updating: &updatedSelection) { value in
                    value.replaceSubrange(value.startIndex..<value.endIndex,
                                          with: AttributedString(newText))
                    Self.applyStyling(to: &value, tint: tint)
                }
                attributed = updated
                if selection != updatedSelection { selection = updatedSelection }
            }
    }

    private var editorText: Binding<AttributedString> {
        Binding {
            attributed
        } set: { value in
            if attributed != value { attributed = value }
            let markdown = String(value.characters)
            if text != markdown { text = markdown }
        }
    }

    private func restyle() {
        var updated = attributed
        var updatedSelection = selection
        // Run after the editor has delivered its text/selection bindings. Change
        // only attributes, letting the SDK keep the caret and selected ranges valid.
        updated.transform(updating: &updatedSelection) { value in
            Self.applyStyling(to: &value, tint: tint)
        }
        // Attribute normalization is idempotent, so its onChange echo stops here.
        // Writing state directly also bypasses the plain-Markdown binding setter.
        if attributed != updated { attributed = updated }
        if selection != updatedSelection { selection = updatedSelection }
    }

    private static func applyStyling(to value: inout AttributedString, tint: Color) {
        let markdown = String(value.characters)
        // Reset our attributes so deleting a heading/list marker removes its style.
        // Leave other attributes alone, including system-owned editing annotations.
        value.font = .system(size: 13, design: .monospaced)
        value.foregroundColor = .primary

        for line in MarkdownLineStyle.parse(markdown) {
            if case .heading(let level) = line.kind,
               let range = Range(line.line, in: value) {
                value[range].font = .system(
                    size: level == 1 ? 22 : 16,
                    weight: .semibold,
                    design: .monospaced
                )
            }
            if let marker = line.marker, let range = Range(marker, in: value) {
                value[range].foregroundColor = tint
            }
        }
    }
}
