import Foundation
import Observation

@Observable @MainActor
public final class UsageStore {
    public var configuration: StoreConfiguration
    public private(set) var states: [ProviderID: ProviderState]
    public private(set) var isRefreshing = false
    public private(set) var lastRefreshAt: Date?

    @ObservationIgnored private let providers: [ProviderID: any UsageProvider]
    @ObservationIgnored private let notifier: (any UsageNotifying)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var notified: NotifiedLevels
    @ObservationIgnored private var lastSuccessAt: [ProviderID: Date] = [:]
    @ObservationIgnored private var failures: [ProviderID: Int] = [:]
    @ObservationIgnored private var nextAttempt: [ProviderID: Date] = [:]
    /// After a 429 even a forced refresh waits: asking again only keeps the server's limit tripped.
    @ObservationIgnored private var rateLimitedUntil: [ProviderID: Date] = [:]
    /// Not ObservationIgnored: views read `displayError`, which depends on it.
    private var lastErrors: [ProviderID: UsageError] = [:]

    private static let notifiedKey = "notifiedLevels.v1"

    public init(
        providers: [any UsageProvider],
        configuration: StoreConfiguration = .init(),
        notifier: (any UsageNotifying)? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.providers = Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        self.configuration = configuration
        self.notifier = notifier
        self.defaults = defaults
        self.now = now
        self.states = Dictionary(uniqueKeysWithValues: self.providers.keys.map { ($0, ProviderState.idle) })
        self.notified = defaults.data(forKey: Self.notifiedKey)
            .flatMap { try? JSONDecoder().decode(NotifiedLevels.self, from: $0) } ?? NotifiedLevels()
    }

    public var registeredProviders: [ProviderID] {
        ProviderID.allCases.filter { providers[$0] != nil }
    }

    public var summaries: [ProviderSummary] {
        registeredProviders
            .filter { configuration.enabled.contains($0) }
            .map { id in
                let state = states[id] ?? .idle
                let window = state.snapshot.flatMap { UsageWindow.mostConstrained(in: $0.windows) }
                let level = window.map { UsageLevel.of($0.usedPercent, thresholds: configuration.thresholds) } ?? .normal
                return ProviderSummary(provider: id, state: state, window: window, level: level, isStale: isStale(id),
                                       displayError: displayError(id))
            }
    }

    public var overall: ProviderSummary? {
        let all = summaries
        guard let best = UsageWindow.mostConstrained(in: all.compactMap(\.window)) else { return nil }
        return all.first { $0.window == best }
    }

    /// The error to show for `id`: the current failure, or the previous one while reloading.
    public func displayError(_ id: ProviderID) -> UsageError? {
        let state = states[id] ?? .idle
        if let error = state.error { return error }
        if case .loading = state { return lastErrors[id] }
        return nil
    }

    public func isStale(_ id: ProviderID) -> Bool {
        guard let fetchedAt = states[id]?.snapshot?.fetchedAt else { return false }
        return now().timeIntervalSince(fetchedAt) > 3 * configuration.refreshInterval.seconds
    }

    public func refreshIfOlder(than age: Duration) async {
        if let last = lastRefreshAt, now().timeIntervalSince(last) <= age.seconds { return }
        await refreshAll()
    }

    public func refreshAll(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let start = now()
        var toFetch: [any UsageProvider] = []
        for id in registeredProviders {
            guard configuration.enabled.contains(id), let provider = providers[id] else {
                states[id] = .idle
                continue
            }
            if let ok = lastSuccessAt[id], ok.addingTimeInterval(provider.minimumInterval.seconds) > start { continue }
            if let until = rateLimitedUntil[id], until > start { continue }
            if !force, let next = nextAttempt[id], next > start { continue }
            states[id] = .loading(last: states[id]?.snapshot)
            toFetch.append(provider)
        }

        await withTaskGroup(of: (ProviderID, Result<UsageSnapshot, UsageError>).self) { group in
            for provider in toFetch {
                group.addTask {
                    do throws(UsageError) { return (provider.id, .success(try await provider.fetch())) }
                    catch { return (provider.id, .failure(error)) }
                }
            }
            for await (id, result) in group {
                await apply(result, for: id)
            }
        }
        lastRefreshAt = now()
    }

    private func apply(_ result: Result<UsageSnapshot, UsageError>, for id: ProviderID) async {
        let last = states[id]?.snapshot
        guard configuration.enabled.contains(id) else {
            states[id] = .idle
            return
        }
        let t = now()
        switch result {
        case .failure(let error):
            states[id] = .failed(error, last: last)
            lastErrors[id] = error
            switch error {
            case .network(let retryAfter):
                nextAttempt[id] = backOff(id, retryAfter: retryAfter, from: t)
            case .rateLimited(let retryAfter):
                let until = backOff(id, retryAfter: retryAfter, from: t)
                nextAttempt[id] = until
                rateLimitedUntil[id] = until
            default:
                break
            }
        case .success(let snapshot):
            states[id] = .loaded(snapshot)
            lastErrors[id] = nil
            lastSuccessAt[id] = t
            failures[id] = 0
            nextAttempt[id] = nil
            let r = evaluate(old: last, new: snapshot, thresholds: configuration.thresholds, notified: notified, now: t)
            notified = r.notified
            if let data = try? JSONEncoder().encode(notified) { defaults.set(data, forKey: Self.notifiedKey) }
            let events = configuration.notifyOnReset ? r.events : r.events.filter { if case .reset = $0 { false } else { true } }
            if configuration.notificationsEnabled, !events.isEmpty {
                await notifier?.deliver(events, snapshot: snapshot)
            }
        }
    }

    /// Counts one more failure and returns when `id` may be tried again.
    private func backOff(_ id: ProviderID, retryAfter: Duration?, from t: Date) -> Date {
        let n = (failures[id] ?? 0) + 1
        failures[id] = n
        let delay = max(retryAfter ?? .zero, Backoff.delay(afterFailures: n, cap: configuration.refreshInterval))
        return t.addingTimeInterval(delay.seconds)
    }
}

private extension Duration {
    var seconds: TimeInterval { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
