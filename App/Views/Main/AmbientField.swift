import SwiftUI
import UsageCore

struct AmbientField: View {
    let page: AppPage
    let selected: ProviderID

    private var leading: Color { ProviderStyle.tint(page == .usage ? .claude : selected) }
    private var trailing: Color { ProviderStyle.tint(page == .usage ? .codex : selected) }
    private var strength: Double { page == .usage ? 1 : 0.45 }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                leading.opacity(0.75 * strength), leading.opacity(0.3 * strength), trailing.opacity(0.3 * strength),
                leading.opacity(0.45 * strength), .clear, trailing.opacity(0.5 * strength),
                leading.opacity(0.15 * strength), .clear, trailing.opacity(0.75 * strength),
            ])
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
