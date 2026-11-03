import SwiftUI
import UsageCore

struct WindowRow: View {
    let window: UsageWindow
    let level: UsageLevel
    var now: Date = .now

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Text(Formatting.title(window.kind))) · \(Int(window.usedPercent.rounded()))%")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let resetsAt = window.resetsAt {
                    Text(Formatting.reset(.make(resetsAt: resetsAt, now: now), now: now))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressBar(fraction: window.fraction, color: level.color ?? .primary)
        }
    }
}

private struct ProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                RoundedRectangle(cornerRadius: 3).fill(color)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}
