import Foundation
import Testing
@testable import UsageCore

@Suite struct TimeoutTests {
    @Test func withTimeoutReturnsValue() async throws {
        let value = try await withTimeout(.seconds(1)) { 42 }
        #expect(value == 42)
    }

    @Test func withTimeoutThrowsWhenSlow() async {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: TimeoutError()) {
            try await withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(5))
                return 1
            }
        }
        #expect(clock.now - start < .seconds(1))
    }
}
