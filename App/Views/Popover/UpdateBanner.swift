import SwiftUI

/// The popover's gentle reminder that a scheduled check found an update.
struct UpdateBanner: View {
    let version: String
    let install: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Agenty \(version) is available")
                .font(.callout)
            Spacer()
            Button("Install…") { install() }
                .buttonStyle(.glass)
        }
    }
}

#Preview {
    UpdateBanner(version: "0.2.1") {}
        .padding(12)
        .frame(width: 340)
}
