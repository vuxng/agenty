import Foundation
import Testing
@testable import UsageCore

@MainActor @Suite final class UsageStoreTests {
    let clock = TestClock()
    /// An absolute-path suite keeps the plist in the temp directory instead of ~/Library/Preferences.
    let suitePath = FileManager.default.temporaryDirectory.appending(path: "agenty-store-\(UUID().uuidString)").path
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suitePath)!
    }

    // A class suite is deallocated after each test, so the throwaway plist never outlives it.
    deinit {
        UserDefaults(suiteName: suitePath)?.removePersistentDomain(forName: suitePath)
        try? FileManager.default.removeItem(atPath: suitePath + ".plist")
    }

    func snap(_ p: ProviderID, _ used: Double = 10, resetsAt: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(
            provider: p, plan: nil,
            windows: [UsageWindow(kind: .weekly, usedPercent: used, resetsAt: resetsAt)],
            credits: nil, fetchedAt: clock.now())
    }
    func makeStore(
        _ providers: [any UsageProvider], config: StoreConfiguration = .init(),
        notifier: (any UsageNotifying)? = nil
    ) -> UsageStore {
        UsageStore(providers: providers, configuration: config, notifier: notifier,
                   defaults: defaults, now: clock.now)
    }

    @Test func refreshLoadsEnabledProviders() async {
        let store = makeStore([
            StubProvider(id: .claude, results: [.success(snap(.claude))]),
            StubProvider(id: .codex, results: [.success(snap(.codex))]),
        ])
        await store.refreshAll()
        #expect(store.states[.claude] == .loaded(snap(.claude)))
        #expect(store.states[.codex] == .loaded(snap(.codex)))
        #expect(store.lastRefreshAt == clock.now())
    }

    @Test func failureIsolatedPerProvider() async {
        let store = makeStore([
            StubProvider(id: .claude, results: [.failure(.network(retryAfter: nil))]),
            StubProvider(id: .codex, results: [.success(snap(.codex))]),
        ])
        await store.refreshAll()
        #expect(store.states[.claude] == .failed(.network(retryAfter: nil), last: nil))
        #expect(store.states[.codex] == .loaded(snap(.codex)))
    }

    @Test func failedStateKeepsLastSnapshot() async {
        let first = snap(.claude)
        let store = makeStore([StubProvider(id: .claude, results: [.success(first), .failure(.tokenExpired)])])
        await store.refreshAll()
        await store.refreshAll()
        #expect(store.states[.claude] == .failed(.tokenExpired, last: first))
    }

    @Test func concurrentRefreshDoesNotOverlap() async {
        let (gate, open) = StubProvider.makeGate()
        let stub = StubProvider(id: .claude, results: [.success(snap(.claude))], gate: gate)
        let store = makeStore([stub])
        let first = Task { @MainActor in await store.refreshAll() }
        while await stub.fetchCount == 0 { await Task.yield() }
        #expect(store.isRefreshing)
        await store.refreshAll() // rejected while the first is suspended on the gate
        open.yield()
        open.finish()
        await first.value
        #expect(await stub.fetchCount == 1)
        #expect(!store.isRefreshing)
        #expect(store.states[.claude] == .loaded(snap(.claude)))
    }

    @Test func networkErrorAppliesBackoff() async {
        let stub = StubProvider(id: .claude, results: [.failure(.network(retryAfter: nil))])
        let store = makeStore([stub])
        await store.refreshAll()
        #expect(await stub.fetchCount == 1)
        clock.advance(by: .seconds(30))
        await store.refreshAll()
        #expect(await stub.fetchCount == 1)
        clock.advance(by: .seconds(31))
        await store.refreshAll()
        #expect(await stub.fetchCount == 2)
    }

    @Test func retryAfterExtendsBackoff() async {
        let stub = StubProvider(id: .claude, results: [.failure(.network(retryAfter: .seconds(600)))])
        let store = makeStore([stub])
        await store.refreshAll()
        clock.advance(by: .seconds(301))
        await store.refreshAll()
        #expect(await stub.fetchCount == 1)
        clock.advance(by: .seconds(300))
        await store.refreshAll()
        #expect(await stub.fetchCount == 2)
    }

    @Test func forceIgnoresBackoffButNotMinimumInterval() async {
        let a = StubProvider(id: .claude, results: [.failure(.network(retryAfter: nil))])
        let b = StubProvider(id: .codex, minimumInterval: .seconds(300), results: [.success(snap(.codex))])
        let store = makeStore([a, b])
        await store.refreshAll()
        #expect(await a.fetchCount == 1)
        #expect(await b.fetchCount == 1)
        await store.refreshAll(force: true)
        #expect(await a.fetchCount == 2)
        #expect(await b.fetchCount == 1)
    }

    @Test func forceSkipsRateLimitedProviderOnly() async {
        let claude = StubProvider(id: .claude, results: [.failure(.rateLimited(retryAfter: nil))])
        let codex = StubProvider(id: .codex, results: [.success(snap(.codex))])
        let store = makeStore([claude, codex])
        await store.refreshAll()
        await store.refreshAll(force: true)
        #expect(await claude.fetchCount == 1)
        #expect(await codex.fetchCount == 2)
        #expect(store.states[.claude] == .failed(.rateLimited(retryAfter: nil), last: nil))
    }

    @Test func rateLimitWithoutRetryAfterHoldsForBackoff() async {
        let stub = StubProvider(id: .claude, results: [.failure(.rateLimited(retryAfter: nil))])
        let store = makeStore([stub])
        await store.refreshAll()
        clock.advance(by: .seconds(59))
        await store.refreshAll(force: true)
        #expect(await stub.fetchCount == 1)
        clock.advance(by: .seconds(2))
        await store.refreshAll(force: true)
        #expect(await stub.fetchCount == 2)
    }

    @Test func rateLimitHoldGrowsWithRepeats() async {
        let stub = StubProvider(id: .claude, results: [.failure(.rateLimited(retryAfter: nil))])
        let store = makeStore([stub])
        await store.refreshAll()
        clock.advance(by: .seconds(61))
        await store.refreshAll(force: true)
        #expect(await stub.fetchCount == 2)
        clock.advance(by: .seconds(61))
        await store.refreshAll(force: true)
        #expect(await stub.fetchCount == 2)
        clock.advance(by: .seconds(60))
        await store.refreshAll(force: true)
        #expect(await stub.fetchCount == 3)
    }

    @Test func retryAfterExtendsRateLimitHold() async {
        let stub = StubProvider(id: .claude, results: [.failure(.rateLimited(retryAfter: .seconds(600)))])
        let store = makeStore([stub])
        await store.refreshAll()
        clock.advance(by: .seconds(599))
        await store.refreshAll(force: true)
        #expect(await stub.fetchCount == 1)
        clock.advance(by: .seconds(2))
        await store.refreshAll(force: true)
        #expect(await stub.fetchCount == 2)
    }

    @Test func successAfterRateLimitLiftsHold() async {
        let recovered = snap(.claude)
        let stub = StubProvider(id: .claude, results: [.failure(.rateLimited(retryAfter: nil)), .success(recovered)])
        let store = makeStore([stub])
        await store.refreshAll()
        clock.advance(by: .seconds(61))
        await store.refreshAll()
        #expect(store.states[.claude] == .loaded(recovered))
        await store.refreshAll(force: true)
        #expect(await stub.fetchCount == 3)
    }

    @Test func disabledProviderIsIdle() async {
        var config = StoreConfiguration()
        config.enabled = [.codex]
        let claude = StubProvider(id: .claude, results: [.success(snap(.claude))])
        let codex = StubProvider(id: .codex, results: [.success(snap(.codex))])
        let store = makeStore([claude, codex], config: config)
        await store.refreshAll()
        #expect(store.states[.claude] == .idle)
        #expect(await claude.fetchCount == 0)
        #expect(store.summaries.map(\.provider) == [.codex])
    }

    @Test func staleAfterThreeIntervals() async {
        let store = makeStore([StubProvider(id: .claude, results: [.success(snap(.claude))])])
        #expect(!store.isStale(.claude))
        await store.refreshAll()
        clock.advance(by: .seconds(899))
        #expect(!store.isStale(.claude))
        clock.advance(by: .seconds(2))
        #expect(store.isStale(.claude))
    }

    @Test func notifiesOnceAcrossStoreInstances() async {
        let notifier = RecordingNotifier()
        let s1 = makeStore([StubProvider(id: .claude, results: [.success(snap(.claude, 81))])], notifier: notifier)
        await s1.refreshAll()
        #expect(await notifier.delivered == [.crossed(.claude, .weekly, threshold: 80)])
        let s2 = makeStore([StubProvider(id: .claude, results: [.success(snap(.claude, 82))])], notifier: notifier)
        await s2.refreshAll()
        #expect(await notifier.delivered.count == 1)
    }

    @Test func resetSuppressedWhenNotifyOnResetOff() async {
        let notifier = RecordingNotifier()
        var config = StoreConfiguration()
        config.notifyOnReset = false
        let past = clock.now().addingTimeInterval(-60)
        let stub = StubProvider(id: .claude, results: [
            .success(snap(.claude, 90, resetsAt: past)), .success(snap(.claude, 5)),
        ])
        let store = makeStore([stub], config: config, notifier: notifier)
        await store.refreshAll()
        await store.refreshAll()
        let delivered = await notifier.delivered
        #expect(delivered == [.crossed(.claude, .weekly, threshold: 80)])
        #expect(!delivered.contains(.reset(.claude, .weekly)))
    }

    @Test func refreshIfOlderThan() async {
        let stub = StubProvider(id: .claude, results: [.success(snap(.claude))])
        let store = makeStore([stub])
        await store.refreshAll()
        await store.refreshIfOlder(than: .seconds(60))
        #expect(await stub.fetchCount == 1)
        clock.advance(by: .seconds(61))
        await store.refreshIfOlder(than: .seconds(60))
        #expect(await stub.fetchCount == 2)
    }

    @Test func overallPicksMostConstrained() async {
        let store = makeStore([
            StubProvider(id: .claude, results: [.success(snap(.claude, 62))]),
            StubProvider(id: .codex, results: [.success(snap(.codex, 23))]),
        ])
        #expect(store.overall == nil)
        await store.refreshAll()
        #expect(store.overall?.provider == .claude)
        #expect(store.overall?.level == .normal)
    }

    @Test func loadingKeepsPreviousError() async {
        let (gate, open) = StubProvider.makeGate()
        open.yield() // lets the first fetch through; the second one blocks
        let stub = StubProvider(id: .claude, results: [.failure(.tokenExpired), .success(snap(.claude))], gate: gate)
        let store = makeStore([stub])
        await store.refreshAll()
        #expect(store.displayError(.claude) == .tokenExpired)
        #expect(store.summaries[0].hasError)

        let second = Task { @MainActor in await store.refreshAll() }
        while await stub.fetchCount < 2 { await Task.yield() }
        #expect(store.states[.claude] == .loading(last: nil))
        #expect(store.summaries[0].hasError)
        #expect(store.displayError(.claude) == .tokenExpired)

        open.yield()
        open.finish()
        await second.value
        #expect(store.displayError(.claude) == nil)
        #expect(!store.summaries[0].hasError)
    }
}
