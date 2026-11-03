import Foundation

/// Decides which notifications a fresh snapshot should fire. Pure: no I/O, no clock.
public func evaluate(
    old: UsageSnapshot?,
    new: UsageSnapshot,
    thresholds: Thresholds,
    notified: NotifiedLevels,
    now: Date
) -> (events: [UsageEvent], notified: NotifiedLevels) {
    var events: [UsageEvent] = []
    var notified = notified
    let provider = new.provider

    for w in new.windows {
        let key = NotifiedLevels.key(provider, w.kind)

        // 1. Reset: reset time passed with usage falling, or a large drop.
        if let o = old?.windows.first(where: { $0.kind == w.kind }) {
            let passedAndDropped = o.resetsAt.map { $0 <= now } == true && w.usedPercent < o.usedPercent
            if passedAndDropped || o.usedPercent - w.usedPercent >= 30 {
                events.append(.reset(provider, w.kind))
                notified.levels[key] = nil
            }
        }

        // 2. Hysteresis: well below warning re-arms the alert.
        if w.usedPercent < Double(thresholds.warning - 5) {
            notified.levels[key] = nil
        }

        // 3. Highest threshold crossed, if above what was already notified.
        let level = [thresholds.warning, thresholds.critical]
            .filter { w.usedPercent >= Double($0) }
            .max()
        if let level, level > (notified.levels[key] ?? 0) {
            events.append(.crossed(provider, w.kind, threshold: level))
            notified.levels[key] = level
        }
    }
    return (events, notified)
}
