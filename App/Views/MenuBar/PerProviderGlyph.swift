import SwiftUI
import UsageCore

struct PerProviderGlyph: View {
    let summaries: [ProviderSummary]
    let palette: GlyphPalette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(summaries) { s in
                HStack(spacing: 3) {
                    // The logo keeps the plain menu-bar color; only the percentage shows the level.
                    ProviderStyle.logo(s.provider)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 11, height: 11)
                        .foregroundStyle(palette.color(for: .normal))
                    Text(s.window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.color(for: s.level))
                }
                .opacity(s.hasError ? 0.4 : 1)
            }
            if summaries.isEmpty {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.color(for: .normal))
            }
        }
    }
}

#Preview("Per provider") { MenuBarPreviewGrid(style: .perProvider) }
