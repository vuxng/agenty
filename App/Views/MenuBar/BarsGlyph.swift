import SwiftUI
import UsageCore

/// Shared coloring for menu bar glyph parts.
struct GlyphPalette {
    let isTemplate: Bool

    func color(for level: UsageLevel) -> Color {
        if isTemplate { return .black }
        return level.color ?? .primary
    }
}

struct BarsGlyph: View {
    let summaries: [ProviderSummary]
    let palette: GlyphPalette

    var body: some View {
        HStack(spacing: 3) {
            ForEach(summaries) { s in
                bar(for: s)
            }
            if summaries.isEmpty {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(palette.color(for: .normal).opacity(0.35))
                    .frame(width: 5, height: 13)
            }
        }
    }

    private func bar(for s: ProviderSummary) -> some View {
        let color = palette.color(for: s.level)
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(color.opacity(0.35))
            .frame(width: 5, height: 13)
            .overlay(alignment: .bottom) {
                if let w = s.window {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: 5, height: 13 * w.fraction)
                }
            }
            .opacity(s.hasError ? 0.4 : 1)
    }
}

#Preview("Bars") { MenuBarPreviewGrid(style: .bars) }
