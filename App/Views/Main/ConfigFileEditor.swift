import SwiftUI

struct ConfigFileEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .autocorrectionDisabled()
            .frame(maxWidth: 720)
    }
}
