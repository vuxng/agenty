import SwiftUI
import UsageCore

@MainActor
struct SaveCapsule: View {
    let document: InstructionsDocument

    var body: some View {
        if document.hasConflict || document.saveError != nil || document.isDirty {
            HStack(spacing: 12) {
                if document.hasConflict || document.saveError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                } else {
                    Circle().fill(.orange).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }

                if document.hasConflict {
                    Text("Changed outside Agenty").font(.callout)
                    Button("Keep Mine") { document.keepMine() }.buttonStyle(.borderless)
                    Button("Reload") { document.reload() }.buttonStyle(.glassProminent)
                } else if let error = document.saveError {
                    Text("Couldn't save: \(reason(for: error))").font(.callout)
                    Button("Try Again") { document.save() }.buttonStyle(.glassProminent)
                } else {
                    Text("Unsaved changes").font(.callout)
                    Button("Revert") { document.revert() }.buttonStyle(.borderless)
                    Button("Save") { document.save() }.buttonStyle(.glassProminent)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
    }

    private func reason(for error: InstructionsError) -> String {
        switch error {
        case .notText: String(localized: "This file isn't plain text, so Agenty can't edit it.")
        case .readFailed(let reason), .writeFailed(let reason): reason
        }
    }
}
