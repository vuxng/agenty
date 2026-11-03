import Foundation
import Testing
@testable import UsageCore

@MainActor @Suite struct UsageStoreTests {
    let clock = TestClock()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!

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
        #expect(store.states[.grok] == nil)
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
}
