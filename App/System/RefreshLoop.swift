import AppKit
import UsageCore

@MainActor
final class RefreshLoop {
    private enum Phase { case idle, refreshing, sleeping }

    private let store: UsageStore
    private var loopTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?
    private var phase = Phase.idle

    init(store: UsageStore) {
        self.store = store
    }

    /// Runs a refresh in an unstructured task so cancelling the caller never reaches the provider fetches.
    private static func shieldedRefresh(_ store: UsageStore, force: Bool) async {
        await Task { await store.refreshAll(force: force) }.value
    }

    func start() {
        stop()
        let store = store
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.phase = .refreshing
                await Self.shieldedRefresh(store, force: false)
                if Task.isCancelled { break }
                self?.phase = .sleeping
                do { try await Task.sleep(for: store.configuration.refreshInterval) } catch { break }
            }
        }
        wakeTask = Task {
            let wakes = NSWorkspace.shared.notificationCenter
                .notifications(named: NSWorkspace.didWakeNotification)
                .map { _ in () }
            for await _ in wakes {
                // Give the network a few seconds to come back; stop() cancels this sleep.
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                Log.refresh.info("wake: forcing refresh")
                await Self.shieldedRefresh(store, force: true)
            }
        }
    }

    /// Restarts only a sleeping loop; a refresh in flight is left alone and the next sleep reads the new interval.
    func intervalDidChange() {
        guard phase == .sleeping else { return }
        start()
    }

    func stop() {
        loopTask?.cancel()
        wakeTask?.cancel()
        loopTask = nil
        wakeTask = nil
        phase = .idle
    }
}
