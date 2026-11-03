import SwiftUI
import UsageCore

struct RingGlyph: View {
    let summary: ProviderSummary?
    let palette: GlyphPalette

    var body: some View {
        HStack(spacing: 4) {
            ring
            if let w = summary?.window {
                Text("\(Int(w.usedPercent.rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.color(for: summary?.level ?? .normal))
            }
        }
        .opacity(summary?.hasError == true ? 0.4 : 1)
    }

    private var ring: some View {
        let color = palette.color(for: summary?.level ?? .normal)
        return ZStack {
            Circle().stroke(color.opacity(0.35), lineWidth: 2.2)
            if let w = summary?.window {
                Circle()
                    .trim(from: 0, to: w.fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(1.1)
        .frame(width: 15, height: 15)
    }
}

#Preview("Single") { MenuBarPreviewGrid(style: .single) }
