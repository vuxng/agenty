import Foundation
import UsageCore

enum ConfigText {
    static func label(_ kind: ConfigChoiceKind, _ value: ConfigValue?) -> String {
        if case .opaque = value { return String(localized: "Custom") }
        switch (kind, value) {
        case (.claudePermission, nil), (.claudePermission, .string("default")),
             (.claudePermission, .string("manual")):
            return String(localized: "Manual")
        case (.claudePermission, .string("dontAsk")): return String(localized: "Don't ask")
        case (.claudePermission, .string("plan")): return String(localized: "Plan")
        case (.claudePermission, .string("acceptEdits")): return String(localized: "Accept edits")
        case (.claudePermission, .string("auto")): return String(localized: "Auto")
        case (.claudePermission, .string("bypassPermissions")): return String(localized: "Bypass")
        case (.claudeSandbox, nil): return String(localized: "Default")
        case (.claudeSandbox, .bool(true)): return String(localized: "On")
        case (.claudeSandbox, .bool(false)): return String(localized: "Off")
        case (_, nil): return String(localized: "Not set")
        case (_, .string(let value)): return value
        case (_, .bool(let value)): return String(value)
        case (_, .opaque): return String(localized: "Custom")
        }
    }

    static func description(_ kind: ConfigChoiceKind, _ value: ConfigValue?) -> String? {
        switch (kind, value) {
        case (.claudePermission, .string("dontAsk")):
            String(localized: "Only runs pre-approved tools; denies everything else")
        case (.claudePermission, .string("plan")):
            String(localized: "Only reads and plans")
        case (.claudePermission, nil), (.claudePermission, .string("default")),
             (.claudePermission, .string("manual")):
            String(localized: "Reads freely; asks before editing files or running commands")
        case (.claudePermission, .string("acceptEdits")):
            String(localized: "Edits files automatically; asks before other commands")
        case (.claudePermission, .string("auto")):
            String(localized: "Does everything automatically, with safety checks in the background")
        case (.claudePermission, .string("bypassPermissions")):
            String(localized: "Skips all checks. Only use in a container or VM")
        case (.codexSandbox, nil), (.codexApproval, nil):
            String(localized: "Codex uses its own default")
        case (.codexSandbox, .string("read-only")):
            String(localized: "Only reads files")
        case (.codexSandbox, .string("workspace-write")):
            String(localized: "Can write in the working directory")
        case (.codexSandbox, .string("danger-full-access")):
            String(localized: "Full access to the machine, without a sandbox")
        case (.codexApproval, .string("untrusted")):
            String(localized: "Runs known safe commands automatically; asks for the rest")
        case (.codexApproval, .string("on-request")):
            String(localized: "The model decides when to ask")
        case (.codexApproval, .string("never")):
            String(localized: "Never asks; errors go straight back to the model")
        default: nil
        }
    }

    static func title(_ kind: ConfigChoiceKind) -> String {
        switch kind {
        case .claudePermission: String(localized: "Permissions")
        case .claudeSandbox, .codexSandbox: String(localized: "Sandbox")
        case .codexApproval: String(localized: "Approval")
        }
    }
}
