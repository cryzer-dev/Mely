// Portions © 2026 Louis Raillé, MIT License — see THIRD_PARTY_NOTICES.md.
import SwiftUI

/// The black island. `topRadius` > 0: convex top corners (expanded);
/// < 0: concave "ears" that blend into the menu bar (hidden, compact); 0: square (mid-animation).
public struct IslandShape: Shape {
    public var width: CGFloat
    public var height: CGFloat
    public var cornerRadius: CGFloat
    public var topRadius: CGFloat

    public init(width: CGFloat, height: CGFloat, cornerRadius: CGFloat, topRadius: CGFloat) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.topRadius = topRadius
    }

    public var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>, CGFloat> {
        get { .init(.init(.init(width, height), cornerRadius), topRadius) }
        set {
            width        = newValue.first.first.first
            height       = newValue.first.first.second
            cornerRadius = newValue.first.second
            topRadius    = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let cr = max(0, min(cornerRadius, height / 2))
        var p = Path()
        if topRadius >= 0 {
            let tr = min(topRadius, min(width / 2, height / 2))
            p.move(to: CGPoint(x: tr, y: 0))
            p.addLine(to: CGPoint(x: width - tr, y: 0))
            p.addArc(center: CGPoint(x: width - tr, y: tr), radius: tr,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: width, y: height - cr))
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: cr, y: height))
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: CGPoint(x: 0, y: tr))
            p.addArc(center: CGPoint(x: tr, y: tr), radius: tr,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            let er = -topRadius
            p.move(to: CGPoint(x: 0, y: 0))
            // Ears flare out at the top so the island blends into the bezel.
            p.addQuadCurve(to: CGPoint(x: er, y: er), control: CGPoint(x: er, y: 0))
            p.addLine(to: CGPoint(x: er, y: height - cr))
            p.addArc(center: CGPoint(x: er + cr, y: height - cr), radius: cr,
                     startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            p.addLine(to: CGPoint(x: width - er - cr, y: height))
            p.addArc(center: CGPoint(x: width - er - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
            p.addLine(to: CGPoint(x: width - er, y: er))
            p.addQuadCurve(to: CGPoint(x: width, y: 0), control: CGPoint(x: width - er, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 0))
        }
        p.closeSubpath()
        return p
    }
}
