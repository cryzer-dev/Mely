import Testing
import Foundation
import CoreGraphics
@testable import MelyCore

@Suite struct FullScreenTests {
    /// Built-in 1512×982 at the origin, an external 1920×1080 to its right, top-aligned.
    let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    let me: Int32 = 1

    func window(_ pid: Int32, _ bounds: CGRect, layer: Int = 0) -> FullScreenDetector.Window {
        .init(pid: pid, layer: layer, bounds: bounds)
    }

    @Test func nativeFullScreenTakesItsScreenOnly() {
        let video = [window(42, builtIn)]
        #expect(FullScreenDetector.isFullScreen(video, screen: builtIn, ownPid: me))
        #expect(!FullScreenDetector.isFullScreen(video, screen: external, ownPid: me))
        #expect(FullScreenDetector.isFullScreen([window(42, external)], screen: external, ownPid: me))
    }

    @Test func aStretchedWindowLeavesTheMenuBar() {
        let zoomed = window(42, CGRect(x: 0, y: 37, width: 1512, height: 945))
        #expect(!FullScreenDetector.isFullScreen([zoomed], screen: builtIn, ownPid: me))
    }

    /// Recorded on a 14" MacBook Pro: TextEdit full screen, then a window stretched to the same size.
    @Test func belowTheNotch() {
        let content = window(42, CGRect(x: 0, y: 33, width: 1512, height: 949))
        let menuBar = window(0, CGRect(x: 0, y: 0, width: 1512, height: 33), layer: 24)
        let clock = window(5, CGRect(x: 1376, y: 0, width: 138, height: 33), layer: 25)
        // Full screen: the app's reveal strip and the menu bar window, but no status items.
        let titleStrip = window(42, CGRect(x: 0, y: 0, width: 1512, height: 33), layer: 26)
        #expect(FullScreenDetector.isFullScreen([titleStrip, menuBar, content], screen: builtIn, topInset: 33, ownPid: me))
        // The desktop: the clock is in the menu bar.
        #expect(!FullScreenDetector.isFullScreen([clock, menuBar, content], screen: builtIn, topInset: 33, ownPid: me))
        // No notch, no exception.
        #expect(!FullScreenDetector.isFullScreen([menuBar, content], screen: builtIn, ownPid: me))
        // Status items on the other screen do not count here.
        let otherClock = window(5, CGRect(x: 3300, y: 0, width: 130, height: 25), layer: 25)
        #expect(FullScreenDetector.isFullScreen([otherClock, content], screen: builtIn, topInset: 33, ownPid: me))
    }

    @Test func whoseWindowCounts() {
        // Not only the active app: the full-screen space stays while the user works elsewhere.
        #expect(FullScreenDetector.isFullScreen([window(7, CGRect(x: 0, y: 0, width: 1512, height: 981)), window(8, .zero)],
                                                screen: builtIn, ownPid: me))
        // Mely's own panels and the menu bar's level do not.
        #expect(!FullScreenDetector.isFullScreen([window(me, builtIn)], screen: builtIn, ownPid: me))
        #expect(!FullScreenDetector.isFullScreen([window(42, builtIn, layer: 24)], screen: builtIn, ownPid: me))
    }

    @Test func readsTheWindowList() {
        let list: [[String: Any]] = [
            [kCGWindowOwnerPID as String: 42, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 1512, height: 982).dictionaryRepresentation],
            [kCGWindowOwnerPID as String: 43],
        ]
        #expect(FullScreenDetector.windows(from: list) == [window(42, builtIn)])
    }

    @Test func appKitFramesTurnIntoCoreGraphics() {
        // The external screen sits lower: AppKit y 0…1080 under a 982-high main screen.
        let appKit = CGRect(x: 1512, y: -98, width: 1920, height: 1080)
        #expect(FullScreenDetector.cgFrame(appKit, mainHeight: 982) == CGRect(x: 1512, y: 0, width: 1920, height: 1080))
        #expect(FullScreenDetector.cgFrame(CGRect(x: 0, y: 0, width: 1512, height: 982), mainHeight: 982) == builtIn)
    }

    @Test func whatEachModeLetsThrough() {
        #expect(FullScreenMode.normal.allows(isRequest: false))
        #expect(FullScreenMode.importantOnly.allows(isRequest: true))
        #expect(!FullScreenMode.importantOnly.allows(isRequest: false))
        #expect(!FullScreenMode.doNotDisturb.allows(isRequest: true))
    }

    @MainActor @Test func settingIsSaved() throws {
        let defaults = try #require(UserDefaults(suiteName: "mely-fullscreen-\(UUID().uuidString)"))
        let behavior = IslandBehavior(defaults: defaults)
        #expect(behavior.fullScreenMode == .importantOnly)
        behavior.fullScreenMode = .doNotDisturb
        #expect(IslandBehavior(defaults: defaults).fullScreenMode == .doNotDisturb)
    }
}
