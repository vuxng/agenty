import Foundation
import Testing
@testable import UsageCore

@Suite struct DateParsingTests {
    @Test func parsesWholeSeconds() {
        #expect(parseISO8601("2026-11-04T16:00:00+00:00") == Date(timeIntervalSince1970: 1_793_808_000))
    }
    @Test func parsesOneFractionalDigit() {
        let d = parseISO8601("2026-11-05T09:00:00.5+00:00")
        #expect(d != nil && abs(d!.timeIntervalSince1970 - 1_793_869_200.5) < 0.001)
    }
    @Test func parsesSixFractionalDigits() {
        let d = parseISO8601("2026-11-04T16:00:00.652364+00:00")
        #expect(d != nil && abs(d!.timeIntervalSince1970 - 1_793_808_000.652364) < 0.001)
    }
    @Test func parsesZSuffix() {
        #expect(parseISO8601("2026-11-04T16:00:00Z") == Date(timeIntervalSince1970: 1_793_808_000))
    }
    @Test func garbageIsNil() {
        #expect(parseISO8601("not a date") == nil)
    }
}
