import AppKit
import MelyCore
import Sparkle

/// In-app updates through Sparkle: the feed is `appcast.xml` of the latest GitHub release
/// (SUFeedURL in Info.plist), each dmg signed with Mely's EdDSA key. A found version is not
/// shown by Sparkle on its own: the island tells about it once and the gear wears a dot;
/// «Обновить» then opens Sparkle's window with what is new, installs and relaunches.
@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    let state: UpdateState
    /// A version to tell about in the island (once per version).
    var announce: ((String) -> Void)?
    private var controller: SPUStandardUpdaterController!
    /// «Проверить сейчас»: a found version opens Sparkle's window at once.
    private var userAsked = false

    static let releasesURL = URL(string: "https://github.com/cryzer-dev/Mely/releases")

    init(state: UpdateState) {
        self.state = state
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    /// Starts the daily checks; nothing for a build without a feed (local runs).
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller.startUpdater()
        let updater = controller.updater
        state.checksAutomatically = updater.automaticallyChecksForUpdates
        state.onChecksAutomaticallyChange = { updater.automaticallyChecksForUpdates = $0 }
        state.checkNow = { [weak self] in self?.checkNow() }
        state.installNow = { [weak self] in self?.installNow() }
    }

    /// «Проверить сейчас»: quiet when there is nothing new.
    func checkNow() {
        guard controller.updater.canCheckForUpdates else { return }
        userAsked = true
        state.phase = .checking
        controller.updater.checkForUpdatesInBackground()
    }

    /// «Обновить»: Sparkle's window with the found version.
    func installNow() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { state.phase = .available(version: version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        MainActor.assumeIsolated {
            state.phase = .upToDate
            userAsked = false
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let code = (error as NSError).code
        MainActor.assumeIsolated {
            // «No update» also ends here on some paths; only a real failure is shown.
            if code != Int(SUError.noUpdateError.rawValue), state.phase == .checking { state.phase = .failed }
            userAsked = false
        }
    }

    // MARK: SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// A scheduled find stays with us (peek and dot); one the user asked for opens at once.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                          andInImmediateFocus immediateFocus: Bool) -> Bool {
        MainActor.assumeIsolated { userAsked }
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            self.state.phase = .available(version: version)
            if handleShowingUpdate { NSApp.activate() } else { announce?(version) }
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { userAsked = false }
    }
}
