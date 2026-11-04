import AppKit
import Observation
import Sparkle

/// Checks for and installs updates with Sparkle. The feed, public key and the
/// daily automatic check come from Info.plist (SUFeedURL, SUPublicEDKey,
/// SUEnableAutomaticChecks).
///
/// Agenty lives in the menu bar, so a scheduled check that finds an update while
/// the user is elsewhere does not pop a window: it sets `availableVersion`, and the
/// popover shows a reminder. Updates found near launch, or asked for by the user,
/// go straight to Sparkle's dialog.
@Observable @MainActor
final class Updater: NSObject {
    /// False in Debug builds: their CFBundleVersion is 1, so every check would find an "update".
    let isEnabled: Bool
    private(set) var canCheckForUpdates = false
    /// Mirrors Sparkle's setting, which Sparkle persists itself.
    var automaticallyChecksForUpdates = false {
        didSet {
            guard automaticallyChecksForUpdates != controller.updater.automaticallyChecksForUpdates else { return }
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    /// The version a gentle reminder is showing, or nil.
    private(set) var availableVersion: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    override init() {
        #if DEBUG
        isEnabled = false
        #else
        isEnabled = true
        #endif
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        if isEnabled {
            controller.startUpdater()
        }
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] updater, _ in
            // Sparkle changes this on the main thread.
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// Opens Sparkle's dialog: checks now, or shows the update a reminder is pointing at.
    func checkForUpdates() {
        guard isEnabled else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}

extension Updater: SPUUpdaterDelegate {}

// The user driver calls these on the main thread; the protocol is not annotated for Swift concurrency.
extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            // A menu bar app is never frontmost on its own: bring the dialog forward.
            NSApp.activate()
        } else {
            availableVersion = update.displayVersionString
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
    }
}
