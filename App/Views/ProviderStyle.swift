import SwiftUI
import UsageCore

enum ProviderStyle {
    static func glyph(_ p: ProviderID) -> String {
        switch p {
        case .claude: "✳"
        case .codex: "◎"
        }
    }

    static func color(_ p: ProviderID) -> Color {
        switch p {
        case .claude: Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
        case .codex: Color(red: 16 / 255, green: 163 / 255, blue: 127 / 255)
        }
    }
}

extension UsageLevel {
    /// `nil` for normal: callers use the template / primary color.
    var color: Color? {
        switch self {
        case .normal: nil
        case .warning: .orange
        case .critical: .red
        }
    }
}
