// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import Testing
import CoreGraphics
@testable import MelyCore

@Suite struct IslandScreenGeometryTests {
    @Test(arguments: [CGFloat(1080), 1920, 2560, 3840])
    func noAuxiliaryAreasMeansNoNotch(screenWidth: CGFloat) {
        let geometry = IslandScreenGeometry(screenWidth: screenWidth, safeAreaTop: 0,
                                            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 30)
        #expect(!geometry.hasNotch)
        #expect(geometry.width == 80)
        #expect(geometry.height == 24)
    }

    @Test func shortMenuBarContainsRestingIsland() {
        let geometry = IslandScreenGeometry(screenWidth: 1920, safeAreaTop: 0,
                                            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 22)
        #expect(geometry.height == 22)
    }

    @Test func macBookNotchKeepsPhysicalSize() {
        let geometry = IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                            auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32)
        #expect(geometry.hasNotch)
        #expect(geometry.width == 192 && geometry.height == 32)
    }

    @Test(arguments: [nil, CGFloat(0), 1000])
    func invalidMeasurementsUseFallback(auxiliaryWidth: CGFloat?) {
        let geometry = IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                            auxiliaryLeftWidth: auxiliaryWidth, auxiliaryRightWidth: auxiliaryWidth,
                                            menuBarHeight: 32)
        #expect(geometry.width == 184 && geometry.height == 32)
    }

    @Test(arguments: [CGFloat(22), 24, 32, 38])
    func characterFitsRestingHeight(height: CGFloat) {
        let layout = IslandRestingLayout(width: 240, height: height)
        #expect(layout.characterCenterY == height / 2)
        #expect(layout.characterCenterY - layout.characterDiameter / 2 >= 3)
        #expect(layout.characterCenterY + layout.characterDiameter / 2 <= height - 3)
    }
}
