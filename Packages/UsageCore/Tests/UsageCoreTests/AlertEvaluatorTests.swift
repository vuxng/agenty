import Foundation
import Testing
@testable import UsageCore

@Suite struct AlertEvaluatorTests {
    let now = Date(timeIntervalSince1970: 1_793_786_400)
    let th = Thresholds()

    func snap(_ windows: [UsageWindow]) -> UsageSnapshot {
        UsageSnapshot(provider: .claude, plan: nil, windows: windows, credits: nil, fetchedAt: now)
    }
    func weekly(_ p: Double, resetsAt: Date? = nil) -> UsageWindow {
        UsageWindow(kind: .weekly, usedPercent: p, resetsAt: resetsAt)
    }
    func notified(_ level: Int) -> NotifiedLevels {
        NotifiedLevels(levels: [NotifiedLevels.key(.claude, .weekly): level])
    }
    func run(old: UsageSnapshot?, new: UsageSnapshot, notified: NotifiedLevels = NotifiedLevels())
        -> (events: [UsageEvent], notified: NotifiedLevels) {
        evaluate(old: old, new: new, thresholds: th, notified: notified, now: now)
    }

    @Test func firstCrossingOfWarning() {
        let r = run(old: nil, new: snap([weekly(81)]))
        #expect(r.events == [.crossed(.claude, .weekly, threshold: 80)])
        #expect(r.notified.levels["claude|weekly"] == 80)
    }

    @Test func noRepeatAtSameLevel() {
        let r = run(old: snap([weekly(82)]), new: snap([weekly(85)]), notified: notified(80))
        #expect(r.events.isEmpty)
    }

    @Test func escalatesToCritical() {
        let r = run(old: snap([weekly(85)]), new: snap([weekly(96)]), notified: notified(80))
        #expect(r.events == [.crossed(.claude, .weekly, threshold: 95)])
        #expect(r.notified.levels["claude|weekly"] == 95)
    }

    @Test func jumpStraightToCriticalEmitsOnlyCritical() {
        let r = run(old: snap([weekly(70)]), new: snap([weekly(96)]))
        #expect(r.events == [.crossed(.claude, .weekly, threshold: 95)])
    }

    @Test func resetWhenResetsAtPassed() {
        let r = run(old: snap([weekly(90, resetsAt: now - 60)]), new: snap([weekly(5)]), notified: notified(95))
        #expect(r.events == [.reset(.claude, .weekly)])
        #expect(r.notified.levels["claude|weekly"] == nil)
    }

    @Test func resetByLargeDrop() {
        let r = run(old: snap([weekly(70, resetsAt: now + 3600)]), new: snap([weekly(35)]))
        #expect(r.events == [.reset(.claude, .weekly)])
    }

    @Test func smallDropIsNotReset() {
        let r = run(old: snap([weekly(70, resetsAt: now + 3600)]), new: snap([weekly(50)]))
        #expect(r.events.isEmpty)
    }

    @Test func largeDropWithoutResetsAt() {
        let r = run(old: snap([weekly(70)]), new: snap([weekly(20)]))
        #expect(r.events == [.reset(.claude, .weekly)])
    }

    @Test func resetThenCrossInSameSnapshot() {
        let r = run(old: snap([weekly(90, resetsAt: now - 60)]), new: snap([weekly(85)]), notified: notified(95))
        #expect(r.events == [.reset(.claude, .weekly), .crossed(.claude, .weekly, threshold: 80)])
        #expect(r.notified.levels["claude|weekly"] == 80)
    }

    @Test func hysteresisClearsBelowWarningMinusFive() {
        let low = run(old: snap([weekly(81)]), new: snap([weekly(74)]), notified: notified(80))
        #expect(low.events.isEmpty)
        #expect(low.notified.levels["claude|weekly"] == nil)
        let again = run(old: snap([weekly(74)]), new: snap([weekly(81)]), notified: low.notified)
        #expect(again.events == [.crossed(.claude, .weekly, threshold: 80)])

        let mid = run(old: snap([weekly(81)]), new: snap([weekly(77)]), notified: notified(80))
        #expect(mid.events.isEmpty)
        #expect(mid.notified == notified(80))
        let next = run(old: snap([weekly(77)]), new: snap([weekly(81)]), notified: mid.notified)
        #expect(next.events.isEmpty)
    }

    @Test func windowsAreIndependent() {
        let s = UsageWindow(kind: .session5h, usedPercent: 81, resetsAt: nil)
        let r = run(old: nil, new: snap([s, weekly(50)]))
        #expect(r.events == [.crossed(.claude, .session5h, threshold: 80)])
    }
}
