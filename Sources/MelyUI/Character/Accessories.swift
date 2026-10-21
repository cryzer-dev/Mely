import SwiftUI
import AppKit
import MelyCore

/// Things to wear (task 6.10), each drawn once around its anchor and scaled to the
/// species' head, eyes, neck or paw. Generic shapes: no logos or film props.
enum AccessoryDrawing {
    static func draw(_ item: Accessory, _ pen: Pen, _ r: CGRect, _ a: Anchors, t: TimeInterval) {
        let s = r.width
        switch item.slot {
        case .head:
            let base = point(r, a.head.x, a.head.y)
            head(item, pen, base, w: s * a.headWidth, t: t)
        case .eyes:
            glasses(item, pen, point(r, a.eyes.x, a.eyes.y), s: s)
        case .neck:
            neck(item, pen, point(r, a.neck.x, a.neck.y), w: s * a.neckWidth, s: s, t: t)
        case .held:
            held(item, pen, point(r, a.held.x, a.held.y), s: s, t: t)
        case .back:
            cape(pen, r)
        }
    }

    // MARK: Head

    private static func head(_ item: Accessory, _ pen: Pen, _ b: CGPoint, w: CGFloat, t: TimeInterval) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: b.x + x * w, y: b.y + y * w) }
        switch item {
        case .wizardHat:
            var cone = Path()
            cone.move(to: pt(-0.36, 0.02))
            cone.addQuadCurve(to: pt(0.12, -0.95), control: pt(-0.05, -0.5))
            cone.addQuadCurve(to: pt(0.36, 0.02), control: pt(0.2, -0.45))
            cone.closeSubpath()
            pen.fill(cone, gradient: [.hex("#5B5BD6"), .hex("#2E2A7A")], from: pt(0, -0.9), to: pt(0, 0))
            pen.fill(Path(ellipseIn: CGRect(x: b.x - w * 0.55, y: b.y - w * 0.07, width: w * 1.1, height: w * 0.16)), .hex("#2E2A7A"))
            for (x, y, k) in [(-0.1, -0.3, 0.0), (0.1, -0.55, 1.0), (0.05, -0.15, 2.0)] {
                let twinkle = 0.6 + 0.4 * sin(t * 3 + k)
                pen.text("✦", size: w * 0.16, weight: .regular, color: CGColor(srgbRed: 1, green: 0.88, blue: 0.4, alpha: twinkle), at: pt(x, y))
            }
        case .witchHat:
            var cone = Path()
            cone.move(to: pt(-0.32, 0))
            cone.addLine(to: pt(-0.05, -0.62))
            cone.addQuadCurve(to: pt(0.4, -0.78), control: pt(0.12, -0.9))
            cone.addQuadCurve(to: pt(0.1, -0.55), control: pt(0.12, -0.7))
            cone.addLine(to: pt(0.32, 0))
            cone.closeSubpath()
            pen.fill(cone, .hex("#2A2433"))
            pen.fill(Path(CGRect(x: b.x - w * 0.31, y: b.y - w * 0.16, width: w * 0.62, height: w * 0.09)), .hex("#8E5BD6"))
            pen.fill(Path(ellipseIn: CGRect(x: b.x - w * 0.62, y: b.y - w * 0.07, width: w * 1.24, height: w * 0.15)), .hex("#2A2433"))
        case .santaHat:
            var cap = Path()
            cap.move(to: pt(-0.42, 0))
            cap.addQuadCurve(to: pt(0.1, -0.62), control: pt(-0.3, -0.62))
            cap.addQuadCurve(to: pt(0.55, -0.15), control: pt(0.45, -0.55))
            cap.addQuadCurve(to: pt(0.42, 0), control: pt(0.3, -0.25))
            cap.closeSubpath()
            pen.fill(cap, gradient: [.hex("#F0454B"), .hex("#B81F2C")], from: pt(0, -0.6), to: pt(0, 0))
            pen.fill(Path(roundedRect: CGRect(x: b.x - w * 0.5, y: b.y - w * 0.1, width: w, height: w * 0.2), cornerRadius: w * 0.1), .hex("#FFFDF8"))
            pen.fill(Path(ellipseIn: CGRect(x: b.x + w * 0.45, y: b.y - w * 0.24, width: w * 0.2, height: w * 0.2)), .hex("#FFFDF8"))
        case .beanie:
            var dome = Path()
            dome.move(to: pt(-0.46, 0))
            dome.addCurve(to: pt(0.46, 0), control1: pt(-0.46, -0.62), control2: pt(0.46, -0.62))
            dome.closeSubpath()
            pen.fill(dome, gradient: [.hex("#5FB3A1"), .hex("#3C8C7C")], from: pt(0, -0.5), to: pt(0, 0))
            for k in -3...3 {
                var rib = Path()
                rib.move(to: pt(CGFloat(k) * 0.11, -0.02))
                rib.addLine(to: pt(CGFloat(k) * 0.08, -0.36))
                pen.stroke(rib, CGColor.black.copy(alpha: 0.12)!, width: w * 0.02)
            }
            pen.fill(Path(roundedRect: CGRect(x: b.x - w * 0.5, y: b.y - w * 0.1, width: w, height: w * 0.18), cornerRadius: w * 0.06), .hex("#2F7568"))
            pen.fill(Path(ellipseIn: CGRect(x: b.x - w * 0.12, y: b.y - w * 0.6, width: w * 0.24, height: w * 0.22)), .hex("#F5EBDD"))
        case .partyHat:
            var cone = Path()
            cone.move(to: pt(-0.26, 0))
            cone.addLine(to: pt(0, -0.72))
            cone.addLine(to: pt(0.26, 0))
            cone.closeSubpath()
            pen.fill(cone, .hex("#FF8FB1"))
            pen.saving {
                pen.cg.addPath(cone.cgPath)
                pen.cg.clip()
                for k in 0..<4 {
                    pen.fill(Path(CGRect(x: b.x - w * 0.3, y: b.y - w * (0.12 + CGFloat(k) * 0.18), width: w * 0.6, height: w * 0.07)), .hex("#FFE066"))
                }
            }
            pen.text("✺", size: w * 0.2, weight: .bold, color: .hex("#7BDFF2"), at: pt(0, -0.74))
        case .crown:
            var crown = Path()
            crown.move(to: pt(-0.34, 0))
            crown.addLine(to: pt(-0.38, -0.36))
            crown.addLine(to: pt(-0.17, -0.18))
            crown.addLine(to: pt(0, -0.42))
            crown.addLine(to: pt(0.17, -0.18))
            crown.addLine(to: pt(0.38, -0.36))
            crown.addLine(to: pt(0.34, 0))
            crown.closeSubpath()
            pen.fill(crown, gradient: [.hex("#FFE27A"), .hex("#F2B33D")], from: pt(0, -0.4), to: pt(0, 0))
            for (x, c) in [(-0.17, "#E8505B"), (0.0, "#4FA3F7"), (0.17, "#5CCB8A")] {
                pen.fill(Path(ellipseIn: CGRect(x: b.x + w * (CGFloat(x) - 0.04), y: b.y - w * 0.12, width: w * 0.08, height: w * 0.08)), .hex(c))
            }
        case .headphones:
            var band = Path()
            band.move(to: pt(-0.5, 0.3))
            band.addCurve(to: pt(0.5, 0.3), control1: pt(-0.55, -0.45), control2: pt(0.55, -0.45))
            pen.stroke(band, .hex("#3A3F4B"), width: w * 0.09)
            for side in [-1.0, 1.0] {
                let cup = CGRect(x: b.x + w * (CGFloat(side) * 0.52 - 0.1), y: b.y + w * 0.2, width: w * 0.2, height: w * 0.3)
                pen.fill(Path(roundedRect: cup, cornerRadius: w * 0.08), .hex("#FF7A8A"))
            }
        default:
            break
        }
    }

    // MARK: Eyes

    private static func glasses(_ item: Accessory, _ pen: Pen, _ c: CGPoint, s: CGFloat) {
        let spacing = s * 0.3, d = s * 0.19
        let frame = CGColor.hex(item == .sunglasses ? "#1E1E24" : "#4A3B33")
        var bridge = Path()
        bridge.move(to: CGPoint(x: c.x - spacing / 2 + d / 2, y: c.y))
        bridge.addQuadCurve(to: CGPoint(x: c.x + spacing / 2 - d / 2, y: c.y), control: CGPoint(x: c.x, y: c.y - s * 0.03))
        pen.stroke(bridge, frame, width: s * 0.022)
        for side in [-1.0, 1.0] {
            let lens = CGRect(x: c.x + CGFloat(side) * spacing / 2 - d / 2, y: c.y - d / 2, width: d, height: d)
            if item == .sunglasses {
                pen.fill(Path(roundedRect: lens, cornerRadius: d * 0.3), gradient: [.hex("#3A3A48"), .hex("#101016")],
                         from: CGPoint(x: lens.midX, y: lens.minY), to: CGPoint(x: lens.midX, y: lens.maxY))
                pen.fill(Path(ellipseIn: CGRect(x: lens.minX + d * 0.18, y: lens.minY + d * 0.15, width: d * 0.22, height: d * 0.14)),
                         CGColor.white.copy(alpha: 0.5)!)
            } else {
                pen.fill(Path(ellipseIn: lens), CGColor.white.copy(alpha: 0.12)!)
                pen.stroke(Path(ellipseIn: lens), frame, width: s * 0.022)
            }
        }
    }

    // MARK: Neck

    private static func neck(_ item: Accessory, _ pen: Pen, _ c: CGPoint, w: CGFloat, s: CGFloat, t: TimeInterval) {
        let band = CGRect(x: c.x - w / 2, y: c.y - s * 0.05, width: w, height: s * 0.1)
        switch item {
        case .stripedScarf:
            let scarf = Path(roundedRect: band, cornerRadius: s * 0.05)
            pen.fill(scarf, .hex("#C8323C"))
            pen.saving {
                pen.cg.addPath(scarf.cgPath)
                pen.cg.clip()
                var x = band.minX
                while x < band.maxX {
                    pen.fill(Path(CGRect(x: x, y: band.minY, width: s * 0.04, height: band.height)), .hex("#F2C14E"))
                    x += s * 0.1
                }
            }
            // The loose end, swinging.
            let swing = 4 * sin(t * 1.5)
            pen.saving {
                let root = CGPoint(x: c.x + w * 0.22, y: c.y)
                pen.cg.translateBy(x: root.x, y: root.y)
                pen.cg.rotate(by: swing * .pi / 180)
                let end = Path(roundedRect: CGRect(x: -s * 0.045, y: 0, width: s * 0.09, height: s * 0.17), cornerRadius: s * 0.02)
                pen.fill(end, .hex("#C8323C"))
                pen.fill(Path(CGRect(x: -s * 0.045, y: s * 0.06, width: s * 0.09, height: s * 0.035)), .hex("#F2C14E"))
            }
        case .garland:
            pen.fill(Path(roundedRect: band.insetBy(dx: 0, dy: s * 0.015), cornerRadius: s * 0.04), .hex("#2E8B57"))
            let bulbs = ["#FF5A5F", "#FFD166", "#4FC3F7", "#9BE564"]
            for k in 0..<7 {
                let x = band.minX + w * (0.08 + CGFloat(k) * 0.14)
                let on = (Int(t * 2) + k) % 2 == 0
                let color = CGColor.hex(bulbs[k % bulbs.count]).copy(alpha: on ? 1 : 0.55)!
                pen.fill(Path(ellipseIn: CGRect(x: x - s * 0.025, y: c.y + s * 0.005, width: s * 0.05, height: s * 0.06)), color)
            }
        case .bowTie:
            let k = s * 0.09
            var bow = Path()
            bow.move(to: c)
            bow.addLine(to: CGPoint(x: c.x - k * 1.3, y: c.y - k * 0.7))
            bow.addLine(to: CGPoint(x: c.x - k * 1.3, y: c.y + k * 0.7))
            bow.closeSubpath()
            bow.move(to: c)
            bow.addLine(to: CGPoint(x: c.x + k * 1.3, y: c.y - k * 0.7))
            bow.addLine(to: CGPoint(x: c.x + k * 1.3, y: c.y + k * 0.7))
            bow.closeSubpath()
            pen.fill(bow, .hex("#E0485A"))
            pen.fill(Path(roundedRect: CGRect(x: c.x - k * 0.3, y: c.y - k * 0.35, width: k * 0.6, height: k * 0.7), cornerRadius: k * 0.15), .hex("#B8303F"))
        default:
            break
        }
    }

    // MARK: Held

    private static func held(_ item: Accessory, _ pen: Pen, _ c: CGPoint, s: CGFloat, t: TimeInterval) {
        switch item {
        case .wand:
            var stick = Path()
            stick.move(to: CGPoint(x: c.x - s * 0.04, y: c.y + s * 0.04))
            stick.addLine(to: CGPoint(x: c.x + s * 0.1, y: c.y - s * 0.22))
            pen.stroke(stick, .hex("#5A3B2A"), width: s * 0.035)
            let glow = 0.6 + 0.4 * sin(t * 4)
            pen.text("✦", size: s * 0.16, weight: .bold, color: CGColor(srgbRed: 1, green: 0.9, blue: 0.45, alpha: glow),
                     at: CGPoint(x: c.x + s * 0.11, y: c.y - s * 0.25))
        case .pumpkin:
            let body = CGRect(x: c.x - s * 0.1, y: c.y - s * 0.08, width: s * 0.2, height: s * 0.16)
            for dx in [-0.05, 0.05, 0.0] {
                pen.fill(Path(ellipseIn: body.offsetBy(dx: s * dx, dy: 0).insetBy(dx: s * 0.03, dy: 0)),
                         .hex(dx == 0 ? "#FF9F1C" : "#F07F13"))
            }
            pen.fill(Path(roundedRect: CGRect(x: c.x - s * 0.015, y: c.y - s * 0.12, width: s * 0.03, height: s * 0.05), cornerRadius: s * 0.01), .hex("#4F7A2B"))
        case .gift:
            let box = CGRect(x: c.x - s * 0.09, y: c.y - s * 0.08, width: s * 0.18, height: s * 0.15)
            pen.fill(Path(roundedRect: box, cornerRadius: s * 0.02), .hex("#4FA3F7"))
            pen.fill(Path(CGRect(x: box.midX - s * 0.018, y: box.minY, width: s * 0.036, height: box.height)), .hex("#FFD166"))
            pen.fill(Path(CGRect(x: box.minX, y: box.minY + s * 0.045, width: box.width, height: s * 0.03)), .hex("#FFD166"))
            for side in [-1.0, 1.0] {
                pen.fill(Path(ellipseIn: CGRect(x: box.midX + CGFloat(side) * s * 0.045 - s * 0.035, y: box.minY - s * 0.05,
                                                width: s * 0.07, height: s * 0.05)), .hex("#FFD166"))
            }
        default:
            break
        }
    }

    // MARK: Back

    /// A cape peeking out on both sides and below.
    private static func cape(_ pen: Pen, _ r: CGRect) {
        var cape = Path()
        cape.move(to: point(r, 0.2, 0.62))
        cape.addQuadCurve(to: point(r, 0.02, 0.98), control: point(r, 0.02, 0.8))
        cape.addLine(to: point(r, 0.98, 0.98))
        cape.addQuadCurve(to: point(r, 0.8, 0.62), control: point(r, 0.98, 0.8))
        cape.closeSubpath()
        pen.fill(cape, gradient: [.hex("#6A3FA0"), .hex("#2A1640")], from: point(r, 0.5, 0.6), to: point(r, 0.5, 1))
    }
}

/// No character: one status icon on a coloured disc (the «значки» look).
struct MinimalDrawing {
    let pose: CharacterPose
    let t: TimeInterval

    func draw(_ pen: Pen, _ r: CGRect) {
        let disc = r.insetBy(dx: r.width * 0.12, dy: r.width * 0.12)
        let pulse = pose == .worried || pose == .curious ? 0.85 + 0.15 * sin(t * 4) : 1
        pen.fill(Path(ellipseIn: disc), Self.color(pose).copy(alpha: pulse)!)
        guard let image = NSImage(systemSymbolName: Self.symbol(pose), accessibilityDescription: pose.title)?
            .withSymbolConfiguration(.init(pointSize: disc.width * 0.5, weight: .bold)) else { return }
        let size = image.size
        let target = CGRect(x: disc.midX - size.width / 2, y: disc.midY - size.height / 2, width: size.width, height: size.height)
        pen.saving {
            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pen.cg, flipped: true)
            let tinted = NSImage(size: size, flipped: false) { rect in
                image.draw(in: rect)
                NSColor.white.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.current = previous
        }
    }

    static func symbol(_ pose: CharacterPose) -> String {
        switch pose {
        case .idle: "circle.fill"
        case .working: "ellipsis"
        case .worried: "hand.raised.fill"
        case .curious: "questionmark"
        case .happy: "checkmark"
        case .scared: "exclamationmark"
        case .sad: "hourglass"
        case .dancing: "music.note"
        case .sleeping: "moon.fill"
        }
    }

    static func color(_ pose: CharacterPose) -> CGColor {
        switch pose {
        case .idle, .sleeping: .hex("#5A5F6A")
        case .working: .hex("#3B9EFF")
        case .worried: .hex("#F5A524")
        case .curious: .hex("#A78BFA")
        case .happy: .hex("#34D399")
        case .scared: .hex("#F4505E")
        case .sad: .hex("#F59E0B")
        case .dancing: .hex("#EC5B99")
        }
    }
}
