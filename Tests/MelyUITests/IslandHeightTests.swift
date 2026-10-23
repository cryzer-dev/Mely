import Testing
import CoreGraphics
import MelyCore
import MelyUI

/// The open island's height: the page, Mely on the left, and what hangs under Mely.
@MainActor @Suite struct IslandHeightTests {
    func island(content: CGFloat, column: CGFloat = 0) -> CGFloat {
        let p = IslandPresentation(geometry: IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32, auxiliaryLeftWidth: 660,
                                                                  auxiliaryRightWidth: 660, menuBarHeight: 32))
        p.mode = .expanded
        p.contentHeight = content
        p.columnHeight = column
        return p.islandSize.height
    }

    @Test func shortPageGrowsForUpdatePill() {
        #expect(island(content: 40, column: 128) == island(content: 40) + 8)
    }

    @Test func tallPageIgnoresColumn() {
        #expect(island(content: 200, column: 128) == island(content: 200))
    }
}
