import Testing
import Foundation
@testable import MelyCore

@MainActor
@Suite struct WhatsNewTests {
    func state() throws -> (WhatsNewState, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "WhatsNewTests-\(UUID().uuidString)"))
        return (WhatsNewState(defaults: defaults), defaults)
    }

    @Test func versions() {
        let card = WhatsNew.current
        #expect(card.matches("1.7") && card.matches("1.7.0") && card.matches("1.7.12"))
        #expect(!card.matches("1.70.0") && !card.matches("1.6.0") && !card.matches("1.6.0-dev") && !card.matches(""))
    }

    @Test func onceAfterTheUpdate() throws {
        let (whatsNew, defaults) = try state()
        whatsNew.showIfNew(appVersion: "1.7.0")
        #expect(whatsNew.isShowing)
        whatsNew.dismiss()
        #expect(!whatsNew.isShowing)
        // Next opening, a restart, a patch release: not again.
        whatsNew.showIfNew(appVersion: "1.7.0")
        #expect(!whatsNew.isShowing)
        let again = WhatsNewState(defaults: defaults)
        again.showIfNew(appVersion: "1.7.1")
        #expect(!again.isShowing)
        // «Что нового» on the preview still opens it.
        again.show()
        #expect(again.isShowing)
    }

    @Test func otherVersionsAndPreview() throws {
        let (whatsNew, defaults) = try state()
        whatsNew.showIfNew(appVersion: "1.6.0")
        #expect(!whatsNew.isShowing)
        defaults.set(true, forKey: WhatsNewState.previewKey)
        whatsNew.showIfNew(appVersion: "1.6.0-dev")
        #expect(whatsNew.isShowing)
        whatsNew.dismiss()
        whatsNew.showIfNew(appVersion: "1.6.0-dev")
        #expect(!whatsNew.isShowing)
    }
}
