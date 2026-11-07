import SwiftUI
import UsageCore

enum MarkdownStyler {
    static func apply(to value: inout AttributedString, tint: Color) {
        let markdown = String(value.characters)
        // Reset our attributes so deleting a heading/list marker removes its style.
        // Leave other attributes alone, including system-owned editing annotations.
        value.font = .system(size: 13, design: .monospaced)
        value.foregroundColor = .primary

        for line in MarkdownLineStyle.parse(markdown) {
            if case .heading(let level) = line.kind,
               let range = Range(line.line, in: value) {
                value[range].font = .system(
                    size: level == 1 ? 22 : 16,
                    weight: .semibold,
                    design: .monospaced
                )
            }
            if let marker = line.marker, let range = Range(marker, in: value) {
                value[range].foregroundColor = tint
            }
        }
    }

    static func styled(_ text: String, tint: Color) -> AttributedString {
        var value = AttributedString(text)
        apply(to: &value, tint: tint)
        return value
    }
}
