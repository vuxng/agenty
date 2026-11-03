import Foundation
import Testing
@testable import UsageCore

@Suite struct CodexRateLimitsMapperTests {
    private let at = Date(timeIntervalSince1970: 1_000)

    private func map(_ json: String) throws(UsageError) -> UsageSnapshot {
        try CodexRateLimitsMapper.snapshot(from: Data(json.utf8), fetchedAt: at)
    }

    @Test func mapsRealFixture() throws {
        let snap = try CodexRateLimitsMapper.snapshot(from: fixture("codex-rate-limits"), fetchedAt: at)
        #expect(snap.provider == .codex)
        #expect(snap.fetchedAt == at)
        #expect(snap.windows == [UsageWindow(kind: .weekly, usedPercent: 23, resetsAt: Date(timeIntervalSince1970: 1_793_905_251))])
        #expect(snap.plan == "pro")
        #expect(snap.credits == Credits(balance: Decimal(string: "61862.9684000000"), unlimited: false))
    }

    @Test func mapsByDurationNotPosition() throws {
        let snap = try map(#"""
        {"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1},
        "secondary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":2},"credits":null,"planType":"plus"}}
        """#)
        #expect(snap.windows.map(\.kind) == [.weekly, .session5h])
        #expect(snap.windows.map(\.usedPercent) == [10, 20])
    }

    @Test func unknownDurations() throws {
        let snap = try map(#"""
        {"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":1440,"resetsAt":null},
        "secondary":{"usedPercent":2,"windowDurationMins":null}}}
        """#)
        #expect(snap.windows.map(\.kind) == [.other(minutes: 1440), .other(minutes: 0)])
        #expect(snap.windows.map(\.resetsAt) == [nil, nil])
        #expect(snap.plan == nil)
    }

    @Test func nullRateLimitsIsNotLoggedIn() {
        #expect(throws: UsageError.notLoggedIn) { try map(#"{"rateLimits":null}"#) }
    }

    @Test func noCreditsWhenHasCreditsFalse() throws {
        let snap = try map(#"{"rateLimits":{"primary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"5"}}}"#)
        #expect(snap.credits == nil)
        #expect(snap.windows.isEmpty)
    }

    @Test func unparseableBalanceIsNil() throws {
        let snap = try map(#"{"rateLimits":{"credits":{"hasCredits":true,"unlimited":true,"balance":"abc"}}}"#)
        #expect(snap.credits == Credits(balance: nil, unlimited: true))
    }

    @Test func invalidJSONIsUnexpectedFormat() {
        #expect(throws: UsageError.self) { try map("not json") }
        #expect(throws: UsageError.self) { try map("[]") }
        #expect(throws: UsageError.self) { try map("{}") }
        #expect(throws: UsageError.self) { try map(#"{"rateLimits":5}"#) }
    }
}
