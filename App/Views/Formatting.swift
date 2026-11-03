import Foundation
import UsageCore

enum Formatting {
    static func title(_ k: WindowKind) -> LocalizedStringResource {
        switch k {
        case .session5h: "5-hour session"
        case .weekly: "Weekly"
        case .weeklyModel(let n): "Weekly · \(n)"
        case .billingPeriod: "Monthly credits"
        case .other(let m): m > 0 ? "\(m / 60)h window" : "Usage"
        }
    }

    static func reset(_ d: ResetDescription, now: Date) -> LocalizedStringResource {
        switch d {
        case .overdue:
            return "resetting…"
        case .relative(let duration):
            // Never show "0m": anything under a minute reads as 1m.
            let totalMinutes = max(1, Int(duration.components.seconds) / 60)
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return hours == 0 ? "resets in \(minutes)m" : "resets in \(hours)h \(minutes)m"
        case .absolute(let date):
            if date.timeIntervalSince(now) < 7 * 86_400 {
                let text = date.formatted(Date.FormatStyle().weekday(.abbreviated).hour().minute())
                return "resets \(text)"
            }
            let text = date.formatted(Date.FormatStyle().month(.abbreviated).day())
            return "resets \(text)"
        }
    }

    static func credits(_ c: Credits) -> String? {
        guard !c.unlimited, let balance = c.balance else { return nil }
        var value = balance
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        let number = rounded.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
        return String(localized: "Credits: \(number)")
    }
}
