// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import CoreGraphics

/// Resting island dimensions, using a physical notch only when the screen has one.
public struct IslandScreenGeometry: Equatable, Sendable {
    public static let fallbackNotchWidth: CGFloat = 184
    private static let noNotchWidth: CGFloat = 80
    private static let noNotchHeight: CGFloat = 24

    public let hasNotch: Bool
    public let width: CGFloat
    public let height: CGFloat

    public init(screenWidth: CGFloat, safeAreaTop: CGFloat,
                auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?,
                menuBarHeight: CGFloat) {
        hasNotch = safeAreaTop > 0
        if hasNotch {
            if let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth {
                let measuredWidth = screenWidth - left - right
                width = measuredWidth > 0 && measuredWidth < screenWidth
                    ? measuredWidth : Self.fallbackNotchWidth
            } else {
                width = Self.fallbackNotchWidth
            }
            height = safeAreaTop
        } else {
            width = Self.noNotchWidth
            height = min(Self.noNotchHeight, menuBarHeight)
        }
    }
}

/// Where the character and the status sit in the compact island.
public struct IslandRestingLayout: Equatable, Sendable {
    public let width: CGFloat
    public let height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    public var characterDiameter: CGFloat { min(26, max(0, height - 6)) }
    public var characterCenterY: CGFloat { height / 2 }
}
