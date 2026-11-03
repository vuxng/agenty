import AppKit
import UsageCore

@MainActor
final class RefreshLoop {
    private let store: UsageStore
    private var loopTask: Task<Void, Never>?
    private var wakeTask: Task<Void, Never>?

    init(store: UsageStore) {
        self.store = store
    }

    func start() {
        stop()
        let store = store
        loopTask = Task {
            while !Task.isCancelled {
                await store.refreshAll()
                do { try await Task.sleep(for: store.configuration.refreshInterval) } catch { break }
            }
        }
        wakeTask = Task {
            let wakes = NSWorkspace.shared.notificationCenter
                .notifications(named: NSWorkspace.didWakeNotification)
                .map { _ in () }
            for await _ in wakes {
                Log.refresh.info("wake: forcing refresh")
                await store.refreshAll(force: true)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        wakeTask?.cancel()
        loopTask = nil
        wakeTask = nil
    }
}
