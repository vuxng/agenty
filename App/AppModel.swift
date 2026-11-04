import Foundation
import Observation
import UsageCore
import UserNotifications

@Observable @MainActor
final class AppModel {
    let store: UsageStore
    let locator: CLILocator
    let notifier = UserNotifier()
    let updater = Updater()

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let loop: RefreshLoop
    @ObservationIgnored private var observer: Task<Void, Never>?
    @ObservationIgnored private let keychainGate: KeychainAccessGate
    @ObservationIgnored private var lastPaths: [ProviderID: String] = [:]
    @ObservationIgnored private var pathRefresh: Task<Void, Never>?

    init() {
        // Writing to a closed child pipe must fail with EPIPE, never kill the app with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runner = SubprocessRunner()
        let locator = CLILocator(home: home, shell: ZshLoginShellLookup(runner: runner))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

        let gate = KeychainAccessGate()
        let claude = ClaudeProvider(
            sources: [
                KeychainCredentialSource(gate: gate),
                FileCredentialSource(url: home.appending(path: ".claude/.credentials.json")),
            ],
            http: URLSessionHTTPClient()
        )
        let codex = CodexProvider(
            locator: locator,
            pathOverride: { UserDefaults.standard.string(forKey: SettingsKey.providerPath(.codex)) },
            runner: runner,
            clientVersion: version
        )

        AppDefaults.register(in: .standard)
        UNUserNotificationCenter.current().delegate = notifier
        self.locator = locator
        self.keychainGate = gate
        self.store = UsageStore(
            providers: [claude, codex],
            configuration: AppDefaults.configuration(from: .standard),
            notifier: notifier
        )
        self.loop = RefreshLoop(store: store)
        self.lastPaths = currentPaths()
        start()
    }

    func start() {
        applySettings()
        Task { [notifier] in await notifier.requestAuthorizationIfNeeded() }
        loop.start()
        observer?.cancel()
        observer = Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: UserDefaults.didChangeNotification)
                .map { _ in () }
            for await _ in changes {
                guard let self else { return }
                self.applySettings()
            }
        }
    }

    /// Forgets a Keychain Deny and tries again (the popover's Retry button).
    func retryKeychainAccess() {
        keychainGate.reset()
        Task { [store] in await store.refreshAll(force: true) }
    }

    private func currentPaths() -> [ProviderID: String] {
        Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
            ($0, defaults.string(forKey: SettingsKey.providerPath($0)) ?? "")
        })
    }

    /// Reads UserDefaults only (never writes), so observing didChangeNotification cannot loop.
    func applySettings() {
        let paths = currentPaths()
        if paths != lastPaths {
            lastPaths = paths
            // Debounced: the user is typing in the path field.
            pathRefresh?.cancel()
            pathRefresh = Task { [store] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await store.refreshAll(force: true)
            }
        }
        let new = AppDefaults.configuration(from: defaults)
        let old = store.configuration
        guard new != old else { return }
        store.configuration = new
        if !new.enabled.subtracting(old.enabled).isEmpty {
            Log.app.info("provider enabled: refreshing")
            Task { [store] in await store.refreshAll(force: true) }
        }
        if new.refreshInterval != old.refreshInterval {
            Log.app.info("refresh interval changed")
            loop.intervalDidChange()
        }
    }
}
