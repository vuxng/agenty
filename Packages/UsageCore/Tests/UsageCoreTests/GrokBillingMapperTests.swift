import Foundation
import Testing
@testable import UsageCore

@Suite struct GrokBillingMapperTests {
    private let at = Date(timeIntervalSince1970: 1_000)

    private func map(_ json: String) throws(UsageError) -> UsageSnapshot {
        try GrokBillingMapper.snapshot(from: Data(json.utf8), fetchedAt: at)
    }

    @Test func mapsRealFixture() throws {
        let snap = try GrokBillingMapper.snapshot(from: fixture("grok-billing"), fetchedAt: at)
        #expect(snap.provider == .grok)
        #expect(snap.fetchedAt == at)
        #expect(snap.windows == [UsageWindow(kind: .weekly, usedPercent: 7,
            resetsAt: Date(timeIntervalSince1970: 1_794_480_227.642))])
        #expect(snap.plan == "SuperGrok Plus")
        #expect(snap.accountEmail == nil)
        #expect(snap.credits == nil)
    }

    @Test(arguments: [#", "type":"USAGE_PERIOD_TYPE_MONTHLY""#, "", #", "type":null"#, #", "type":7"#])
    func otherOrMissingTypeIsBillingPeriod(_ type: String) throws {
        let snap = try map("""
        {"config":{"creditUsagePercent":12,"currentPeriod":{"end":"2026-11-12T10:43:47.642+00:00"\(type)}}}
        """)
        #expect(snap.windows == [UsageWindow(kind: .billingPeriod, usedPercent: 12,
            resetsAt: Date(timeIntervalSince1970: 1_794_480_227.642))])
        #expect(snap.plan == nil)
        #expect(snap.accountEmail == nil)
        #expect(snap.credits == nil)
    }

    @Test(arguments: [#", "subscription_tier":"""#, #", "subscription_tier":null"#,
                      #", "subscription_tier":7"#, #", "subscription_tier":false"#])
    func emptyOrNonStringTierIsNil(_ tier: String) throws {
        let snap = try map("""
        {"config":{"creditUsagePercent":0,"currentPeriod":{"end":"2026-11-12T10:43:47Z"}}\(tier)}
        """)
        #expect(snap.plan == nil)
        #expect(snap.windows == [UsageWindow(kind: .billingPeriod, usedPercent: 0,
            resetsAt: Date(timeIntervalSince1970: 1_794_480_227))])
    }

    @Test(arguments: ["", #""creditUsagePercent":null,"#, #""creditUsagePercent":"7","#,
                      #""creditUsagePercent":true,"#, #""creditUsagePercent":[],"#,
                      #""creditUsagePercent":{},"#])
    func missingOrNonNumericPercentThrows(_ percent: String) {
        #expect(throws: UsageError.unexpectedFormat("grok config has no creditUsagePercent")) {
            try map("""
            {"config":{\(percent)"currentPeriod":{"end":"2026-11-12T10:43:47Z"}}}
            """)
        }
    }

    @Test(arguments: ["1e20", "-1"])
    func unsafePercentThrows(_ percent: String) {
        #expect(throws: UsageError.unexpectedFormat("grok config has no creditUsagePercent")) {
            try map("""
            {"config":{"creditUsagePercent":\(percent),"currentPeriod":{"end":"2026-11-12T10:43:47Z"}}}
            """)
        }
    }

    @Test func overagePercentIsPreserved() throws {
        let snap = try map("""
        {"config":{"creditUsagePercent":150,"currentPeriod":{"end":"2026-11-12T10:43:47Z"}}}
        """)
        #expect(snap.windows == [UsageWindow(kind: .billingPeriod, usedPercent: 150,
            resetsAt: Date(timeIntervalSince1970: 1_794_480_227))])
    }

    @Test(arguments: ["", #""end":"not a date""#, #""end":null"#, #""end":7"#,
                      #""end":false"#, #""end":[]"#, #""end":{}"#])
    func missingOrInvalidEndThrows(_ end: String) {
        #expect(throws: UsageError.unexpectedFormat("grok currentPeriod has no valid end")) {
            try map("""
            {"config":{"creditUsagePercent":7,"currentPeriod":{\(end)}}}
            """)
        }
    }

    @Test(arguments: ["", #", "currentPeriod":null"#, #", "currentPeriod":7"#,
                      #", "currentPeriod":[]"#])
    func missingOrInvalidPeriodThrows(_ period: String) {
        #expect(throws: UsageError.unexpectedFormat("grok currentPeriod has no valid end")) {
            try map("""
            {"config":{"creditUsagePercent":7\(period)}}
            """)
        }
    }

    @Test(arguments: ["{}", #"{"config":null}"#, #"{"config":[]}"#, #"{"config":7}"#])
    func missingOrInvalidConfigThrows(_ json: String) {
        #expect(throws: UsageError.unexpectedFormat("grok config has no creditUsagePercent")) {
            try map(json)
        }
    }

    @Test(arguments: ["not json", "[]", "null", "7", #""text""#])
    func nonObjectResultIsUnexpectedFormat(_ json: String) {
        #expect(throws: UsageError.unexpectedFormat("grok result is not a JSON object")) {
            try map(json)
        }
    }
}
