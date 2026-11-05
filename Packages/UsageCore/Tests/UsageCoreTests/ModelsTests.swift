import Foundation
import Testing
@testable import UsageCore

@Suite struct ModelsTests {
    @Test func windowKindStorageKeys() {
        #expect(WindowKind.session5h.storageKey == "session5h")
        #expect(WindowKind.weekly.storageKey == "weekly")
        #expect(WindowKind.weeklyModel("Opus").storageKey == "weeklyModel:Opus")
        #expect(WindowKind.billingPeriod.storageKey == "billingPeriod")
        #expect(WindowKind.other(minutes: 1440).storageKey == "other:1440")
    }

    @Test func mostConstrainedPicksHighestThenLaterReset() {
        let a = UsageWindow(kind: .session5h, usedPercent: 40, resetsAt: Date(timeIntervalSince1970: 100))
        let b = UsageWindow(kind: .weekly, usedPercent: 62, resetsAt: Date(timeIntervalSince1970: 200))
        let c = UsageWindow(kind: .weeklyModel("Opus"), usedPercent: 62, resetsAt: Date(timeIntervalSince1970: 300))
        #expect(UsageWindow.mostConstrained(in: [a, b, c]) == c)
        #expect(UsageWindow.mostConstrained(in: []) == nil)
        // khi % bằng nhau, resetsAt == nil được coi là sớm nhất nên thua mọi ngày cụ thể
        let d = UsageWindow(kind: .other(minutes: 0), usedPercent: 62, resetsAt: nil)
        #expect(UsageWindow.mostConstrained(in: [d, b]) == b)
    }

    @Test func fractionClamps() {
        #expect(UsageWindow(kind: .weekly, usedPercent: 130, resetsAt: nil).fraction == 1.0)
        #expect(UsageWindow(kind: .weekly, usedPercent: -5, resetsAt: nil).fraction == 0.0)
        #expect(UsageWindow(kind: .weekly, usedPercent: 45, resetsAt: nil).fraction == 0.45)
    }

    @Test func sharesResetIgnoresSubMinuteDifferences() throws {
        // The fixture's weekly and Fable rows are one reset, 0.65s apart.
        let w = try ClaudeUsageParser.windows(from: fixture("claude-oauth-usage"))
        #expect(w[1].sharesReset(with: w[0]))
    }

    @Test func sharesResetIsFalseForDifferentOrMissingResets() {
        let t = Date(timeIntervalSince1970: 1_000)
        let a = UsageWindow(kind: .weekly, usedPercent: 1, resetsAt: t)
        let later = UsageWindow(kind: .weeklyModel("Fable"), usedPercent: 1, resetsAt: t.addingTimeInterval(60))
        let none = UsageWindow(kind: .weeklyModel("Opus"), usedPercent: 1, resetsAt: nil)
        #expect(!a.sharesReset(with: later))
        #expect(!a.sharesReset(with: none))
        #expect(!none.sharesReset(with: none))
    }

    @Test func usageLevelBoundaries() {
        let t = Thresholds()
        #expect(UsageLevel.of(79.9, thresholds: t) == .normal)
        #expect(UsageLevel.of(80, thresholds: t) == .warning)
        #expect(UsageLevel.of(95, thresholds: t) == .critical)
        #expect(UsageLevel.of(130, thresholds: t) == .critical)
    }

    @Test func resetDescriptionRelativeUnder24h() {
        let now = Date(timeIntervalSince1970: 1_793_786_400)
        #expect(ResetDescription.make(resetsAt: now + 2*3600 + 13*60 + 30, now: now) == .relative(.seconds(7980)))
    }

    @Test func resetDescriptionAbsoluteFrom24h() {
        let now = Date(timeIntervalSince1970: 1_793_786_400)
        #expect(ResetDescription.make(resetsAt: now + 86_400, now: now) == .absolute(now + 86_400))
    }

    @Test func resetDescriptionOverdue() {
        let now = Date(timeIntervalSince1970: 1_793_786_400)
        #expect(ResetDescription.make(resetsAt: now - 60, now: now) == .overdue)
        #expect(ResetDescription.make(resetsAt: now, now: now) == .overdue)
    }
}
