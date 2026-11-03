import AppKit
import SwiftUI
import UsageCore

/// Content drawn into the menu bar image. Pure value inputs so it renders anywhere.
struct MenuBarContent: View {
    let style: MenuBarStyle
    let summaries: [ProviderSummary]
    let overall: ProviderSummary?
    let palette: GlyphPalette

    var body: some View {
        glyph
            .padding(3)
            .overlay(alignment: .topTrailing) {
                if summaries.contains(where: \.hasError) {
                    Circle().fill(.orange).frame(width: 4, height: 4)
                }
            }
            .fixedSize()
    }

    @ViewBuilder private var glyph: some View {
        switch style {
        case .bars: BarsGlyph(summaries: summaries, palette: palette)
        case .single: RingGlyph(summary: overall, palette: palette)
        case .perProvider: PerProviderGlyph(summaries: summaries, palette: palette)
        }
    }
}

@MainActor
enum MenuBarRenderer {
    /// Template only when every summary is normal and none has an error.
    static func isTemplate(_ summaries: [ProviderSummary]) -> Bool {
        summaries.allSatisfy { $0.level == .normal && !$0.hasError }
    }

    static func render(
        style: MenuBarStyle,
        summaries: [ProviderSummary],
        overall: ProviderSummary?,
        colorScheme: ColorScheme
    ) -> NSImage {
        let template = isTemplate(summaries)
        let content = MenuBarContent(
            style: style, summaries: summaries, overall: overall,
            palette: GlyphPalette(isTemplate: template)
        )
        .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return NSImage() }
        let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        image.isTemplate = template
        return image
    }
}
