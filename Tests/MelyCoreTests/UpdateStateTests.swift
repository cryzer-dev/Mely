import Testing
import Foundation
@testable import MelyCore

@MainActor
@Suite struct UpdateStateTests {
    func defaults() -> UserDefaults {
        let name = "mely-update-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func announcesEachVersionOnce() {
        let d = defaults()
        let state = UpdateState(currentVersion: "1.2.0")
        #expect(state.shouldAnnounce("1.3.0", defaults: d))
        #expect(!state.shouldAnnounce("1.3.0", defaults: d))
        #expect(state.shouldAnnounce("1.3.1", defaults: d))
    }

    @Test func dotOnlyWhileAVersionWaits() {
        let state = UpdateState(currentVersion: "1.2.0")
        #expect(!state.hasPendingUpdate)
        state.phase = .available(version: "1.3.0")
        #expect(state.hasPendingUpdate)
        #expect(state.statusText == "Доступна 1.3.0")
        state.phase = .upToDate
        #expect(!state.hasPendingUpdate)
    }

    @Test func justUpdatedAfterANewerVersionOnly() {
        let d = defaults()
        #expect(UpdateState.justUpdated(current: "1.2.0", defaults: d) == nil) // first launch
        #expect(UpdateState.justUpdated(current: "1.2.0", defaults: d) == nil) // same version
        #expect(UpdateState.justUpdated(current: "1.3.0", defaults: d) == "1.3.0")
        #expect(UpdateState.justUpdated(current: "1.3.0", defaults: d) == nil)
        #expect(UpdateState.justUpdated(current: "1.4.0-dev", defaults: d) == nil) // local build
        #expect(UpdateState.justUpdated(current: "1.2.9", defaults: d) == nil) // went back
    }

    @Test func versionsCompareByNumbers() {
        #expect(UpdateState.isNewer("1.10.0", than: "1.9.9"))
        #expect(UpdateState.isNewer("2.0", than: "1.99.99"))
        #expect(!UpdateState.isNewer("1.2.0", than: "1.2.0-dev"))
        #expect(!UpdateState.isNewer("1.2.0", than: "1.2.1"))
    }
}
