import Foundation
import Testing
@testable import UsageCore

@Suite struct ClaudeUsageParserTests {
    @Test func parsesRealFixture() throws {
        let w = try ClaudeUsageParser.windows(from: fixture("claude-oauth-usage"))
        #expect(w.count == 1)   // weekly_scoped "Fable" is_active=false is dropped
        #expect(w[0].kind == .weekly && w[0].usedPercent == 13)
        #expect(abs(w[0].resetsAt!.timeIntervalSince1970 - 1_793_822_400.652364) < 0.001)
    }

    @Test func mapsLimitKindsInOrder() throws {
        let json = #"""
        {"limits":[
          {"kind":"session","percent":45,"resets_at":"2026-11-04T16:00:00+00:00","is_active":true,"scope":null},
          {"kind":"weekly_all","percent":62,"resets_at":"2026-11-05T09:00:00+00:00","is_active":true,"scope":null},
          {"kind":"weekly_scoped","percent":84,"resets_at":"2026-11-05T09:00:00+00:00","is_active":true,
           "scope":{"model":{"id":null,"display_name":"Opus"},"surface":null}},
          {"kind":"monthly_magic","percent":10,"resets_at":null,"is_active":true,"scope":null}]}
        """#
        let w = try ClaudeUsageParser.windows(from: Data(json.utf8))
        #expect(w.map(\.kind) == [.session5h, .weekly, .weeklyModel("Opus")])
        #expect(w.map(\.usedPercent) == [45, 62, 84])
    }

    @Test func skipsInactiveRows() throws {
        let json = #"""
        {"limits":[
          {"kind":"weekly_all","percent":62,"resets_at":"2026-11-05T09:00:00+00:00","is_active":false,"scope":null}]}
        """#
        #expect(try ClaudeUsageParser.windows(from: Data(json.utf8)).isEmpty)
    }

    @Test func emptyLimitsIsEmpty() throws {
        #expect(try ClaudeUsageParser.windows(from: Data(#"{"limits":[]}"#.utf8)).isEmpty)
    }

    @Test func scopedFallsBackToModelIdThenSkips() throws {
        let json = #"""
        {"limits":[
          {"kind":"weekly_scoped","percent":5,"resets_at":null,"is_active":true,
           "scope":{"model":{"id":"claude-x","display_name":null},"surface":null}},
          {"kind":"weekly_scoped","percent":6,"resets_at":null,"is_active":true,
           "scope":{"model":{"id":null,"display_name":null},"surface":null}},
          {"kind":"weekly_scoped","percent":7,"resets_at":null,"is_active":true,"scope":null}]}
        """#
        let w = try ClaudeUsageParser.windows(from: Data(json.utf8))
        #expect(w.map(\.kind) == [.weeklyModel("claude-x")])
    }

    @Test func badResetsAtKeepsRow() throws {
        let json = #"{"limits":[{"kind":"session","percent":1,"resets_at":"garbage","is_active":true}]}"#
        let w = try ClaudeUsageParser.windows(from: Data(json.utf8))
        #expect(w.count == 1 && w[0].resetsAt == nil)
    }

    @Test func fallsBackToLegacyFields() throws {
        let json = #"""
        {"five_hour":{"utilization":45.0,"resets_at":"2026-11-04T16:00:00+00:00"},
         "seven_day":{"utilization":62.0,"resets_at":"2026-11-05T09:00:00.5+00:00"},
         "seven_day_opus":{"utilization":30.0,"resets_at":null},"seven_day_sonnet":null,"iguana_necktie":{}}
        """#
        let w = try ClaudeUsageParser.windows(from: Data(json.utf8))
        #expect(w.map(\.kind) == [.session5h, .weekly, .weeklyModel("Opus")])
        #expect(w[2].resetsAt == nil)
    }

    @Test(arguments: [#"{"tangelo":null}"#, "not json", "[1,2]"])
    func throwsUnexpectedFormat(_ body: String) {
        let error = #expect(throws: UsageError.self) { try ClaudeUsageParser.windows(from: Data(body.utf8)) }
        guard case .unexpectedFormat(let reason) = error else {
            Issue.record("expected .unexpectedFormat, got \(String(describing: error))")
            return
        }
        #expect(!reason.contains(body))
    }
}
