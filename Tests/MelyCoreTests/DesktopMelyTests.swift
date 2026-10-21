import Testing
import CoreGraphics
@testable import MelyCore

@Suite struct DesktopMelyTests {
    @Test func droppedStaysAndAlertsCallItBack() {
        var m = DesktopMelyMachine()
        #expect(m.launched(alert: false) == .none)
        m.dropped()
        #expect(m.phase == .onDesktop && m.wantsDesktop)
        // An approval: to the notch, and back out once answered.
        #expect(m.alertChanged(active: true) == .retract)
        #expect(m.phase == .awayForAlert)
        #expect(m.alertChanged(active: true) == .none)
        #expect(m.alertChanged(active: false) == .flyOut)
        #expect(m.landed(alert: false) == .none)
        #expect(m.phase == .onDesktop)
    }

    @Test func alertDuringTheFlightSendsItBackOnLanding() {
        var m = DesktopMelyMachine(wantsDesktop: true)
        #expect(m.launched(alert: false) == .flyOut)
        #expect(m.alertChanged(active: true) == .none)
        #expect(m.landed(alert: true) == .retract)
        #expect(m.phase == .awayForAlert)
    }

    @Test func launchWaitsForAnAlert() {
        var m = DesktopMelyMachine(wantsDesktop: true)
        #expect(m.launched(alert: true) == .none)
        #expect(m.phase == .awayForAlert)
        #expect(m.alertChanged(active: false) == .flyOut)
    }

    @Test func sentHomeIsRemembered() {
        var m = DesktopMelyMachine()
        m.dropped()
        #expect(m.sentHome() == .flyHome)
        #expect(!m.wantsDesktop && m.phase == .home)
        // Home while called back for an alert: it does not come out after.
        m.dropped()
        _ = m.alertChanged(active: true)
        #expect(m.sentHome() == .none)
        #expect(m.alertChanged(active: false) == .none)
    }

    @Test func hotKeyToggles() {
        var m = DesktopMelyMachine()
        #expect(m.toggled(alert: false) == .flyOut)
        #expect(m.landed(alert: false) == .none)
        #expect(m.toggled(alert: false) == .flyHome)
        #expect(m.phase == .home)
    }

    @Test func geometry() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let p = DesktopMelyLogic.clamp(CGPoint(x: -50, y: 2000), visibleFrame: screen)
        #expect(p == CGPoint(x: 24, y: 944 - 120 - 24))
        #expect(DesktopMelyLogic.isOverBody(CGPoint(x: 60, y: 60)))
        #expect(!DesktopMelyLogic.isOverBody(CGPoint(x: 5, y: 5)))
        #expect(DesktopMelyLogic.shouldSleep(idleFor: 121, mouseDistance: 400))
        #expect(!DesktopMelyLogic.shouldSleep(idleFor: 121, mouseDistance: 100))
        #expect(!DesktopMelyLogic.shouldSleep(idleFor: 60, mouseDistance: 400))
        let r = DesktopMelyLogic.appKitRect(fromQuartz: CGRect(x: 10, y: 0, width: 100, height: 50), mainScreenHeight: 944)
        #expect(r == CGRect(x: 10, y: 894, width: 100, height: 50))
    }
}
