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
        MarkdownStyler.apply(to: &initial, tint: tint)
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
                    MarkdownStyler.apply(to: &value, tint: tint)
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
            MarkdownStyler.apply(to: &value, tint: tint)
        }
        // Attribute normalization is idempotent, so its onChange echo stops here.
        // Writing state directly also bypasses the plain-Markdown binding setter.
        if attributed != updated { attributed = updated }
        if selection != updatedSelection { selection = updatedSelection }
    }
}
