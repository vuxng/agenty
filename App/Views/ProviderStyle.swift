import SwiftUI
import UsageCore

enum ProviderStyle {
    /// Provider colors for the ambient background and Markdown marks.
    static func tint(_ p: ProviderID) -> Color {
        switch p {
        case .claude: Color(red: 217.0 / 255, green: 120.0 / 255, blue: 87.0 / 255)
        case .codex: Color(red: 107.0 / 255, green: 107.0 / 255, blue: 242.0 / 255)
        }
    }

    /// Single-color logo that takes the foreground style, for the menu bar.
    static func logo(_ p: ProviderID) -> Image {
        switch p {
        case .claude: Image(.claudeLogo)
        case .codex: Image(.codexLogo)
        }
    }

    /// The logo in its own brand colors, for the popover.
    static func brandLogo(_ p: ProviderID) -> Image {
        switch p {
        case .claude: Image(.claudeBrandLogo)
        case .codex: Image(.codexBrandLogo)
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
