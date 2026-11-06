import Foundation

enum AppPage: String, CaseIterable, Identifiable {
    case usage, instructions, config

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .usage: "Usage"
        case .instructions: "Instructions"
        case .config: "Config"
        }
    }
}
