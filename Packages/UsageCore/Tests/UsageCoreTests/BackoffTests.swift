import Testing
@testable import UsageCore

@Suite struct BackoffTests {
    @Test func delays() {
        let cap = Duration.seconds(300)
        #expect(Backoff.delay(afterFailures: 0, cap: cap) == .zero)
        #expect(Backoff.delay(afterFailures: 1, cap: cap) == .seconds(60))
        #expect(Backoff.delay(afterFailures: 2, cap: cap) == .seconds(120))
        #expect(Backoff.delay(afterFailures: 3, cap: cap) == .seconds(240))
        #expect(Backoff.delay(afterFailures: 5, cap: cap) == .seconds(300))
        #expect(Backoff.delay(afterFailures: 500, cap: cap) == .seconds(300))
    }
}
