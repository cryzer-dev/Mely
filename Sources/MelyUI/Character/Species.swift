import SwiftUI
import AppKit
import MelyCore

/// Where things are worn on a species, in its unit square (y down). One set for every
/// pose: the characters are round and keep their shape, the pose moves them as a whole.
struct Anchors {
    /// Brim centre of a hat, and how wide the head is there.
    var head = CGPoint(x: 0.5, y: 0.26)
    var headWidth = 0.56
    /// The eye line (glasses).
    var eyes = CGPoint(x: 0.5, y: 0.575)
    /// Where a scarf goes round, and how wide.
    var neck = CGPoint(x: 0.5, y: 0.84)
    var neckWidth = 0.78
    /// The paw holding a thing.
    var held = CGPoint(x: 0.86, y: 0.8)
    var cheekX = [0.24, 0.76]
    var cheekY = 0.66
}

/// The user's settings for a look, read the way the drawing needs them.
struct SpeciesPaint {
    let values: [String: CustomizationValue]
    /// A session's colour, over the look's own.
    let tint: CGColor?

    func color(_ id: String = "color", default fallback: String) -> CGColor {
        if id == "color", let tint { return tint }
        return CGColor.hex(values[id]?.color ?? fallback)
    }

    func flag(_ id: String) -> Bool { values[id]?.bool ?? true }
    func choice(_ id: String, default fallback: String) -> String { values[id]?.choice ?? fallback }
    var cheeks: Bool { flag("cheeks") }
}

struct BodyContext {
    let pen: Pen
    let r: CGRect
    let pose: CharacterPose
    let t: TimeInterval
    let paint: SpeciesPaint
    let outfit: [AccessorySlot: Accessory]

    var wearsHat: Bool { outfit[.head] != nil }

    func p(_ x: Double, _ y: Double) -> CGPoint { point(r, x, y) }
    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { rect(r, x, y, w, h) }

    /// Light on top, shade at the bottom: the soft look all characters share.
    func fillBody(_ path: Path, _ base: CGColor) {
        pen.fill(path, gradient: [base.mixed(with: .white, 0.45), base],
                 from: p(0.5, 0.2), to: p(0.5, 0.95))
    }
}

/// A Canvas character's body. The face (eyes, brows, mouth), the poses' moves and signs,
/// and the clothes are shared; a species draws what is around them.
protocol Species {
    var anchors: Anchors { get }
    /// A beak replaces the mouth.
    var hasBeak: Bool { get }
    /// Behind the body: ears, horns, a tail, a leaf.
    func drawBack(_ c: BodyContext)
    func drawBody(_ c: BodyContext)
    /// Over the face: a nose, a beak.
    func drawFront(_ c: BodyContext)
    /// Slots that would look wrong in a pose.
    func hiddenSlots(_ pose: CharacterPose) -> Set<AccessorySlot>
}

extension Species {
    var anchors: Anchors { Anchors() }
    var hasBeak: Bool { false }
    func drawBack(_ c: BodyContext) {}
    func drawFront(_ c: BodyContext) {}
    /// Asleep, nothing in the paws.
    func hiddenSlots(_ pose: CharacterPose) -> Set<AccessorySlot> { pose == .sleeping ? [.held] : [] }
}

enum SpeciesCatalog {
    static func named(_ id: String) -> any Species {
        switch id {
        case BuiltInLooks.fawn.id: Fawn()
        case BuiltInLooks.lamb.id: Lamb()
        case BuiltInLooks.conure.id: Conure()
        case BuiltInLooks.fox.id: Fox()
        default: Bun()
        }
    }
}

// MARK: - Росток

/// Mely itself: the soft bun with a leaf from the logo.
struct Bun: Species {
    func drawBack(_ c: BodyContext) {
        guard c.paint.flag("leaf"), !c.wearsHat else { return }
        let base = c.p(0.5, 0.23)
        let sway = c.pose == .dancing ? 12 * sin(c.t * 2 * .pi * 0.95 + 0.6) : 4 * sin(c.t * 1.3)
        c.pen.saving {
            c.pen.cg.translateBy(x: base.x, y: base.y)
            c.pen.cg.rotate(by: sway * .pi / 180)
            c.pen.cg.translateBy(x: -base.x, y: -base.y)
            c.pen.fill(MelyLogo.leaf(in: c.r), gradient: [.hex("#8CD980"), .hex("#4DAD66")],
                       from: c.p(0.5, 0), to: c.p(0.8, 0.2))
        }
    }

    func drawBody(_ c: BodyContext) {
        let base = c.paint.color(default: "#FFF6EE")
        // The cream default keeps the logo's exact gradient.
        if c.paint.tint == nil, c.paint.values["color"]?.color ?? "#FFF6EE" == "#FFF6EE" {
            c.pen.fill(MelyLogo.body(in: c.r), gradient: [.hex("#FFFAF2"), .hex("#FFE6D6")], from: c.p(0.5, 0.2), to: c.p(0.5, 1))
        } else {
            c.fillBody(MelyLogo.body(in: c.r), base)
        }
    }
}

// MARK: - Оленёнок

struct Fawn: Species {
    var anchors: Anchors { var a = Anchors(); a.head = CGPoint(x: 0.5, y: 0.25); return a }

    func drawBack(_ c: BodyContext) {
        let fur = c.paint.color(default: "#C98A5B")
        // Antlers: two little forked nubs.
        if c.paint.flag("antlers"), !c.wearsHat {
            let horn = CGColor.hex("#7A5236")
            for side in [-1.0, 1.0] {
                var a = Path()
                a.move(to: c.p(0.5 + side * 0.12, 0.26))
                a.addQuadCurve(to: c.p(0.5 + side * 0.17, 0.06), control: c.p(0.5 + side * 0.1, 0.14))
                a.move(to: c.p(0.5 + side * 0.135, 0.15))
                a.addLine(to: c.p(0.5 + side * 0.22, 0.12))
                c.pen.stroke(a, horn, width: c.r.width * 0.045)
            }
        }
        // Ears out to the sides, a little droopy, swinging slowly.
        let flick = 4 * sin(c.t * 1.1)
        for side in [-1.0, 1.0] {
            let root = c.p(0.5 + side * 0.27, 0.37)
            c.pen.saving {
                c.pen.cg.translateBy(x: root.x, y: root.y)
                c.pen.cg.rotate(by: (side * (-28 + flick)) * .pi / 180)
                let w = c.r.width * 0.23, h = c.r.width * 0.13
                let outer = Path(ellipseIn: CGRect(x: side < 0 ? -w : 0, y: -h / 2, width: w, height: h))
                c.pen.fill(outer, fur)
                let inner = Path(ellipseIn: CGRect(x: side < 0 ? -w * 0.85 : w * 0.15, y: -h * 0.28, width: w * 0.7, height: h * 0.56))
                c.pen.fill(inner, .hex("#F7C6C0"))
            }
        }
    }

    func drawBody(_ c: BodyContext) {
        let fur = c.paint.color(default: "#C98A5B")
        let body = MelyLogo.body(in: c.r)
        c.fillBody(body, fur)
        c.pen.saving {
            c.pen.cg.addPath(body.cgPath)
            c.pen.cg.clip()
            // Pale face and belly.
            c.pen.fill(Path(ellipseIn: c.box(0.2, 0.5, 0.6, 0.5)), fur.mixed(with: .white, 0.7))
            if c.paint.flag("spots") {
                for (x, y, d) in [(0.24, 0.36, 0.06), (0.74, 0.33, 0.05), (0.83, 0.47, 0.045), (0.14, 0.5, 0.045), (0.62, 0.27, 0.04)] {
                    c.pen.fill(Path(ellipseIn: c.box(x - d / 2, y - d / 2, d, d * 0.85)), CGColor.white.copy(alpha: 0.85)!)
                }
            }
        }
    }

    func drawFront(_ c: BodyContext) {
        c.pen.fill(Path(ellipseIn: c.box(0.465, 0.635, 0.07, 0.045)), .hex("#3B2A26"))
    }
}

// MARK: - Барашек

struct Lamb: Species {
    var anchors: Anchors {
        var a = Anchors()
        a.head = CGPoint(x: 0.5, y: 0.22)
        a.headWidth = 0.6
        a.cheekX = [0.3, 0.7]
        a.cheekY = 0.665
        return a
    }

    func hiddenSlots(_ pose: CharacterPose) -> Set<AccessorySlot> {
        // Curled up asleep, the scarf disappears in the wool.
        pose == .sleeping ? [.held, .neck] : []
    }

    private func puffs(_ c: BodyContext) -> [(Double, Double, Double)] {
        // Around the outline of the bun body: a cloud.
        var list: [(Double, Double, Double)] = []
        for k in 0..<12 {
            let a = Double(k) / 12 * 2 * .pi
            list.append((0.5 + 0.36 * cos(a), 0.6 + 0.29 * sin(a), 0.11))
        }
        return list
    }

    func drawBack(_ c: BodyContext) {
        let face = c.paint.color("face", default: "#E9C9AE")
        // Ears hanging beside the face.
        let flick = 5 * sin(c.t * 1.2)
        for side in [-1.0, 1.0] {
            let root = c.p(0.5 + side * 0.24, 0.5)
            c.pen.saving {
                c.pen.cg.translateBy(x: root.x, y: root.y)
                c.pen.cg.rotate(by: side * (20 + flick) * .pi / 180)
                let w = c.r.width * 0.26, h = c.r.width * 0.12
                c.pen.fill(Path(ellipseIn: CGRect(x: side < 0 ? -w : 0, y: -h / 2, width: w, height: h)), face)
            }
        }
    }

    func drawBody(_ c: BodyContext) {
        let wool = c.paint.color(default: "#FBF7F0")
        var cloud = Path()
        for (x, y, d) in puffs(c) { cloud.addEllipse(in: c.box(x - d, y - d, 2 * d, 2 * d)) }
        cloud.addEllipse(in: c.box(0.14, 0.3, 0.72, 0.6))
        c.fillBody(cloud, wool)
        // Horns curling at the sides, in front of the wool.
        if c.paint.flag("horns") {
            for side in [-1.0, 1.0] {
                var h = Path()
                let cx = 0.5 + side * 0.31, cy = 0.45
                h.move(to: c.p(cx - side * 0.04, cy - 0.08))
                h.addCurve(to: c.p(cx + side * 0.03, cy + 0.08), control1: c.p(cx + side * 0.1, cy - 0.12),
                           control2: c.p(cx + side * 0.12, cy + 0.06))
                h.addQuadCurve(to: c.p(cx, cy), control: c.p(cx - side * 0.04, cy + 0.07))
                c.pen.stroke(h, .hex("#C9A27A"), width: c.r.width * 0.05)
            }
        }
        // The face: an oval under a tuft of wool.
        let face = c.paint.color("face", default: "#E9C9AE")
        c.pen.fill(Path(ellipseIn: c.box(0.22, 0.44, 0.56, 0.42)), face.mixed(with: .white, 0.25))
        for (x, d) in [(0.38, 0.09), (0.5, 0.1), (0.62, 0.09)] {
            c.pen.fill(Path(ellipseIn: c.box(x - d, 0.42 - d, 2 * d, 2 * d)), wool.mixed(with: .white, 0.4))
        }
    }

    func drawFront(_ c: BodyContext) {
        c.pen.fill(Path(ellipseIn: c.box(0.47, 0.64, 0.06, 0.035)), .hex("#7A5A50"))
    }
}

// MARK: - Аратинга

/// A sun conure: round, warm feathers, white eye rings and a hooked beak.
struct Conure: Species {
    var hasBeak: Bool { true }
    var anchors: Anchors { var a = Anchors(); a.head = CGPoint(x: 0.5, y: 0.25); return a }

    private func colors(_ c: BodyContext) -> (top: CGColor, bottom: CGColor, face: CGColor, wing: CGColor) {
        if let tint = c.paint.tint { return (tint.mixed(with: .white, 0.3), tint, tint.mixed(with: .hex("#FF7A1A"), 0.3), tint.mixed(with: .black, 0.25)) }
        switch c.paint.choice("plumage", default: "sun") {
        case "green": return (.hex("#9FDB7A"), .hex("#4FAF5A"), .hex("#FFC94A"), .hex("#2F7D4A"))
        case "blue": return (.hex("#A8DDFF"), .hex("#4A90E2"), .hex("#E9F4FF"), .hex("#2C5FA8"))
        default: return (.hex("#FFDA4A"), .hex("#FF9A2E"), .hex("#FF7A1A"), .hex("#3FA55A"))
        }
    }

    func drawBack(_ c: BodyContext) {
        guard c.paint.flag("crest"), !c.wearsHat else { return }
        let col = colors(c)
        let ruffle = 5 * sin(c.t * 1.6)
        for (k, a) in [-22.0, 0, 22].enumerated() {
            let root = c.p(0.5, 0.25)
            c.pen.saving {
                c.pen.cg.translateBy(x: root.x, y: root.y)
                c.pen.cg.rotate(by: (a + ruffle * Double(k - 1)) * .pi / 180)
                let w = c.r.width * 0.09, h = c.r.width * 0.22
                c.pen.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h, width: w, height: h)), col.top)
            }
        }
    }

    func drawBody(_ c: BodyContext) {
        let col = colors(c)
        let body = MelyLogo.body(in: c.r)
        c.pen.fill(body, gradient: [col.top, col.bottom], from: c.p(0.5, 0.25), to: c.p(0.5, 0.95))
        c.pen.saving {
            c.pen.cg.addPath(body.cgPath)
            c.pen.cg.clip()
            // Orange mask round the eyes.
            c.pen.fill(Path(ellipseIn: c.box(0.18, 0.44, 0.64, 0.32)), col.face.copy(alpha: 0.85)!)
            // Wings folded at the sides, the tips another colour.
            let flap = c.pose == .happy || c.pose == .dancing ? 6 * sin(c.t * 2 * .pi * 1.8) : 0
            for side in [-1.0, 1.0] {
                let root = c.p(0.5 + side * 0.4, 0.62)
                c.pen.saving {
                    c.pen.cg.translateBy(x: root.x, y: root.y)
                    c.pen.cg.rotate(by: side * (12 + flap) * .pi / 180)
                    let w = c.r.width * 0.2, h = c.r.width * 0.36
                    c.pen.fill(Path(ellipseIn: CGRect(x: -w / 2, y: -h * 0.2, width: w, height: h)),
                               gradient: [col.bottom, col.wing], from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: h * 0.8))
                }
            }
        }
        // White rings round the eyes.
        for x in [0.35, 0.65] {
            c.pen.fill(Path(ellipseIn: c.box(x - 0.1, 0.475, 0.2, 0.2)), CGColor.white.copy(alpha: 0.95)!)
        }
    }

    func drawFront(_ c: BodyContext) {
        let ink = CGColor.hex("#3A3437")
        // Hooked upper beak; open when happy, singing or startled.
        let open = c.pose == .happy || c.pose == .dancing || c.pose == .scared || c.pose == .curious
        if open {
            var lower = Path()
            lower.move(to: c.p(0.455, 0.7))
            lower.addQuadCurve(to: c.p(0.545, 0.7), control: c.p(0.5, 0.79))
            lower.closeSubpath()
            c.pen.fill(lower, ink.mixed(with: .white, 0.15))
        }
        var upper = Path()
        upper.move(to: c.p(0.44, 0.645))
        upper.addQuadCurve(to: c.p(0.56, 0.645), control: c.p(0.5, 0.6))
        upper.addQuadCurve(to: c.p(0.5, open ? 0.71 : 0.74), control: c.p(0.565, 0.7))
        upper.addQuadCurve(to: c.p(0.44, 0.645), control: c.p(0.435, 0.7))
        c.pen.fill(upper, ink)
    }
}

// MARK: - Лисёнок

struct Fox: Species {
    var anchors: Anchors { var a = Anchors(); a.head = CGPoint(x: 0.5, y: 0.25); a.headWidth = 0.52; return a }

    private func colors(_ c: BodyContext) -> (fur: CGColor, light: CGColor, tip: CGColor) {
        if let tint = c.paint.tint { return (tint, .hex("#FFF8F0"), tint.mixed(with: .black, 0.5)) }
        switch c.paint.choice("fur", default: "red") {
        case "arctic": return (.hex("#EEF1F6"), .hex("#FFFFFF"), .hex("#B8C2D0"))
        case "silver": return (.hex("#6B6F7C"), .hex("#E9EAF0"), .hex("#2E3038"))
        default: return (.hex("#F28C3C"), .hex("#FFF4E8"), .hex("#4A2C22"))
        }
    }

    func drawBack(_ c: BodyContext) {
        let col = colors(c)
        if c.paint.flag("tail") {
            // A bushy tail curling up behind, swishing.
            let swish = 6 * sin(c.t * 1.4) + (c.pose == .happy || c.pose == .dancing ? 10 * sin(c.t * 2 * .pi * 1.5) : 0)
            let root = c.p(0.66, 0.86)
            c.pen.saving {
                c.pen.cg.translateBy(x: root.x, y: root.y)
                c.pen.cg.rotate(by: swish * .pi / 180)
                let s = c.r.width
                var tail = Path()
                tail.move(to: .zero)
                tail.addCurve(to: CGPoint(x: s * 0.24, y: -s * 0.6), control1: CGPoint(x: s * 0.34, y: -s * 0.1),
                              control2: CGPoint(x: s * 0.36, y: -s * 0.5))
                tail.addCurve(to: CGPoint(x: s * 0.02, y: -s * 0.26), control1: CGPoint(x: s * 0.1, y: -s * 0.58),
                              control2: CGPoint(x: s * 0.1, y: -s * 0.36))
                tail.closeSubpath()
                c.pen.fill(tail, gradient: [col.fur.mixed(with: .white, 0.2), col.fur], from: CGPoint(x: 0, y: -s * 0.5), to: .zero)
                c.pen.saving {
                    c.pen.cg.addPath(tail.cgPath)
                    c.pen.cg.clip()
                    c.pen.fill(Path(ellipseIn: CGRect(x: s * 0.1, y: -s * 0.68, width: s * 0.26, height: s * 0.2)), col.light)
                }
            }
        }
        // Pointed ears, dark tips, pale inside; one twitches now and then.
        let twitch = (c.t.truncatingRemainder(dividingBy: 5.2)) < 0.2 ? 8.0 : 0
        for side in [-1.0, 1.0] {
            let root = c.p(0.5 + side * 0.24, 0.3)
            c.pen.saving {
                c.pen.cg.translateBy(x: root.x, y: root.y)
                c.pen.cg.rotate(by: side * (14 + (side > 0 ? twitch : 0)) * .pi / 180)
                let s = c.r.width
                var ear = Path()
                ear.move(to: CGPoint(x: -s * 0.13, y: s * 0.06))
                ear.addLine(to: CGPoint(x: 0, y: -s * 0.24))
                ear.addLine(to: CGPoint(x: s * 0.13, y: s * 0.06))
                ear.closeSubpath()
                c.pen.fill(ear, col.fur)
                c.pen.saving {
                    c.pen.cg.addPath(ear.cgPath)
                    c.pen.cg.clip()
                    c.pen.fill(Path(CGRect(x: -s * 0.2, y: -s * 0.3, width: s * 0.4, height: s * 0.13)), col.tip)
                }
                var inner = Path()
                inner.move(to: CGPoint(x: -s * 0.065, y: s * 0.04))
                inner.addLine(to: CGPoint(x: 0, y: -s * 0.12))
                inner.addLine(to: CGPoint(x: s * 0.065, y: s * 0.04))
                inner.closeSubpath()
                c.pen.fill(inner, col.light.copy(alpha: 0.9)!)
            }
        }
    }

    func drawBody(_ c: BodyContext) {
        let col = colors(c)
        let body = MelyLogo.body(in: c.r)
        c.fillBody(body, col.fur)
        c.pen.saving {
            c.pen.cg.addPath(body.cgPath)
            c.pen.cg.clip()
            // White cheeks and chest.
            var muzzle = Path()
            muzzle.move(to: c.p(0.06, 0.6))
            muzzle.addQuadCurve(to: c.p(0.5, 0.64), control: c.p(0.3, 0.56))
            muzzle.addQuadCurve(to: c.p(0.94, 0.6), control: c.p(0.7, 0.56))
            muzzle.addLine(to: c.p(0.94, 1))
            muzzle.addLine(to: c.p(0.06, 1))
            muzzle.closeSubpath()
            c.pen.fill(muzzle, col.light)
        }
    }

    func drawFront(_ c: BodyContext) {
        c.pen.fill(Path(ellipseIn: c.box(0.465, 0.632, 0.07, 0.045)), .hex("#2B1F1C"))
    }
}

// MARK: - Colours

extension CGColor {
    /// `#RRGGBB`; grey when it does not parse.
    static func hex(_ string: String) -> CGColor {
        let digits = string.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { return CGColor(gray: 0.6, alpha: 1) }
        return CGColor(srgbRed: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                       blue: Double(v & 0xFF) / 255, alpha: 1)
    }

    /// sRGB components, alpha last.
    var rgba: [CGFloat] {
        guard let c = converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components else {
            return [0.6, 0.6, 0.6, 1]
        }
        return c.count >= 4 ? c : c.count == 2 ? [c[0], c[0], c[0], c[1]] : [0.6, 0.6, 0.6, 1]
    }

    /// `w` of the way towards `other`.
    func mixed(with other: CGColor, _ w: CGFloat) -> CGColor {
        let a = rgba, b = other.rgba
        return CGColor(srgbRed: a[0] + (b[0] - a[0]) * w, green: a[1] + (b[1] - a[1]) * w,
                       blue: a[2] + (b[2] - a[2]) * w, alpha: a[3])
    }
}
