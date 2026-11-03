import Foundation
import Observation
import UsageCore
import UserNotifications

@Observable @MainActor
final class AppModel {
    let store: UsageStore
    let locator: CLILocator
    let notifier = UserNotifier()

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let loop: RefreshLoop
    @ObservationIgnored private var observer: Task<Void, Never>?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let runner = SubprocessRunner()
        let locator = CLILocator(home: home, shell: ZshLoginShellLookup(runner: runner))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

        let claude = ClaudeProvider(
            sources: [
                KeychainCredentialSource(),
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
        self.store = UsageStore(
            providers: [claude, codex],
            configuration: AppDefaults.configuration(from: .standard),
            notifier: notifier
        )
        self.loop = RefreshLoop(store: store)
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

    /// Reads UserDefaults only (never writes), so observing didChangeNotification cannot loop.
    func applySettings() {
        let new = AppDefaults.configuration(from: defaults)
        let old = store.configuration
        guard new != old else { return }
        store.configuration = new
        if new.refreshInterval != old.refreshInterval {
            Log.app.info("refresh interval changed")
            loop.intervalDidChange()
        }
    }
}
