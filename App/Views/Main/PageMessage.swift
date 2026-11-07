import SwiftUI

struct PageMessage<Actions: View>: View {
    let systemImage: String
    let text: String
    private let actions: Actions

    init(systemImage: String, text: String, @ViewBuilder actions: () -> Actions) {
        self.systemImage = systemImage
        self.text = text
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: text)
            actions
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
