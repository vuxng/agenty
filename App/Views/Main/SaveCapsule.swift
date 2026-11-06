import SwiftUI
import UsageCore

@MainActor
protocol SaveCapsuleModel: AnyObject {
    var isDirty: Bool { get }
    var hasConflict: Bool { get }
    var saveFailureReason: String? { get }
    func save() async
    func revert()
    func keepMine() async
    func reload() async
}

extension InstructionsDocument: SaveCapsuleModel {
    var saveFailureReason: String? {
        guard let saveError else { return nil }
        switch saveError {
        case .notText: return String(localized: "This file isn't plain text, so Agenty can't edit it.")
        case .readFailed(let reason), .writeFailed(let reason): return reason
        }
    }
}

extension ConfigDocument: SaveCapsuleModel {
    var saveFailureReason: String? { saveError?.failureReason }
}

extension ConfigError {
    var failureReason: String {
        switch self {
        case .cliNotFound: String(localized: "Codex CLI not found. Choose its path to use Controls.")
        case .unsupportedCLI: String(localized: "This Codex CLI doesn't support Controls. Update Codex or edit the file.")
        case .conflict: String(localized: "Changed outside Agenty")
        case .invalidFile(let reason): String(localized: "Invalid config file: \(reason)")
        case .invalidValue(let reason): String(localized: "Invalid config value: \(reason)")
        case .readFailed(let reason): String(localized: "Agenty can't read this file: \(reason)")
        case .writeFailed(let reason): String(localized: "Agenty can't write this file: \(reason)")
        }
    }
}

@MainActor
struct SaveCapsule: View {
    let document: any SaveCapsuleModel
    var onSave: (() -> Void)? = nil

    var body: some View {
        if document.hasConflict || document.saveFailureReason != nil || document.isDirty {
            HStack(spacing: 12) {
                if document.hasConflict || document.saveFailureReason != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                } else {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }

                if document.hasConflict {
                    Text("Changed outside Agenty").font(.callout)
                    Button("Keep Mine") { Task { await document.keepMine() } }.buttonStyle(.borderless)
                    Button("Reload") { Task { await document.reload() } }.buttonStyle(.glassProminent)
                } else if let reason = document.saveFailureReason {
                    Text("Couldn't save: \(reason)").font(.callout)
                    Button("Try Again", action: save).buttonStyle(.glassProminent)
                } else {
                    Text("Unsaved changes").font(.callout)
                    Button("Revert") { document.revert() }.buttonStyle(.borderless)
                    Button("Save", action: save).buttonStyle(.glassProminent)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
    }

    private func save() {
        if let onSave {
            onSave()
        } else {
            Task { await document.save() }
        }
    }
}
