import Testing
import CoreGraphics
import MelyUI
@testable import MelyFixtures

/// The rules on hand-made frames: each catches what it is for and lets the rest be.
@Suite struct LayoutRulesTests {
    let island = LayoutProbe(id: "island", frame: CGRect(x: 0, y: 0, width: 640, height: 300))

    @Test func outsideItsContainer() {
        let out = LayoutProbe(id: "a", frame: CGRect(x: 600, y: 10, width: 60, height: 20), inside: "island")
        let fine = LayoutProbe(id: "b", frame: CGRect(x: 10, y: 10, width: 60, height: 20), inside: "island")
        #expect(LayoutRules.inside([island, out, fine]).count == 1)
    }

    @Test func scrollingContainerChecksOnlyAcross() {
        let list = LayoutProbe(id: "list", frame: CGRect(x: 0, y: 0, width: 300, height: 100), scrolls: true)
        let below = LayoutProbe(id: "row", frame: CGRect(x: 0, y: 400, width: 300, height: 40), inside: "list")
        let wide = LayoutProbe(id: "wide", frame: CGRect(x: 0, y: 10, width: 320, height: 40), inside: "list")
        #expect(LayoutRules.inside([list, below, wide]) == ["wide выходит за list: (0,10 320×40) вне (0,0 300×100)"])
    }

    @Test func rowOverlap() {
        let notch = LayoutProbe(id: "notch", frame: CGRect(x: 220, y: 0, width: 200, height: 32), row: "header")
        let tab = LayoutProbe(id: "tab", frame: CGRect(x: 200, y: 5, width: 32, height: 22), row: "header")
        let icon = LayoutProbe(id: "icon", frame: CGRect(x: 430, y: 5, width: 26, height: 22), row: "header")
        #expect(LayoutRules.rows([notch, tab, icon]) == ["notch и tab наезжают друг на друга в ряду header"])
    }

    @Test func emptyCapsule() {
        let pill = LayoutProbe(id: "header.usage", frame: CGRect(x: 0, y: 0, width: 14, height: 22), contains: "plan.gauge")
        #expect(LayoutRules.contains([pill]) == ["header.usage без содержимого (plan.gauge)"])
        let gauge = LayoutProbe(id: "plan.gauge", frame: CGRect(x: 7, y: 5, width: 30, height: 12))
        let full = LayoutProbe(id: "header.usage", frame: CGRect(x: 0, y: 0, width: 44, height: 22), contains: "plan.gauge")
        #expect(LayoutRules.contains([full, gauge]).isEmpty)
        #expect(LayoutRules.nonEmpty([LayoutProbe(id: "z", frame: CGRect(x: 0, y: 0, width: 0, height: 22))]).count == 1)
        #expect(LayoutRules.nonEmpty([LayoutProbe(id: "slot", frame: CGRect(x: 40, y: 10, width: 0, height: 0))]).isEmpty)
    }

    @Test func cutText() {
        let cut = LayoutProbe(id: "t", frame: CGRect(x: 0, y: 0, width: 100, height: 16), idealHeight: 32)
        let fits = LayoutProbe(id: "u", frame: CGRect(x: 0, y: 0, width: 100, height: 32), idealHeight: 32.4)
        #expect(LayoutRules.text([cut, fits]).count == 1)
    }

    @Test func chatAtRest() {
        let viewport = LayoutProbe(id: "chat.viewport", frame: CGRect(x: 0, y: 40, width: 400, height: 160), scrolls: true)
        let first = LayoutProbe(id: "chat.message.1", frame: CGRect(x: 0, y: 42, width: 400, height: 30))
        let fade = LayoutProbe(id: "chat.fade", frame: CGRect(x: 0, y: 40, width: 400, height: 12))
        let cutLast = LayoutProbe(id: "chat.message.2", frame: CGRect(x: 0, y: 80, width: 400, height: 140))
        let problems = LayoutRules.chat([viewport, first, fade, cutLast])
        #expect(problems.count == 2)
        let whole = LayoutProbe(id: "chat.message.2", frame: CGRect(x: 0, y: 80, width: 400, height: 100))
        #expect(LayoutRules.chat([viewport, first, whole]).isEmpty)
    }
}
