import AppKit
import SwiftUI
import UsageCore

struct PerProviderGlyph: View {
    let summaries: [ProviderSummary]
    let palette: GlyphPalette

    /// The menu bar's own text size (13 pt), so the percentages match other menu bar items.
    private static let fontSize = NSFont.menuBarFont(ofSize: 0).pointSize

    var body: some View {
        HStack(spacing: 8) {
            ForEach(summaries) { s in
                HStack(spacing: 4) {
                    // The logo keeps the plain menu-bar color; only the percentage shows the level.
                    ProviderStyle.logo(s.provider)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(palette.color(for: .normal))
                    Text(s.window.map { "\(Int($0.usedPercent.rounded()))%" } ?? "—")
                        .font(.system(size: Self.fontSize, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.color(for: s.level))
                }
                .opacity(s.hasError ? 0.4 : 1)
            }
            if summaries.isEmpty {
                Text("—")
                    .font(.system(size: Self.fontSize))
                    .foregroundStyle(palette.color(for: .normal))
            }
        }
    }
}

#Preview("Per provider") { MenuBarPreviewGrid(style: .perProvider) }
