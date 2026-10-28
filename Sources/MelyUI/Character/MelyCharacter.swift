import SwiftUI
import AppKit
import MelyCore

/// Mely alive (task 6.12): the bun from the logo, breathing, blinking, following the
/// pointer, with a face and a move for each pose.
///
/// Drawn with Core Graphics in its own NSView on its own timer: animated inside the
/// island's SwiftUI graph, every frame re-laid out the whole island (~10% CPU). Here a
/// frame redraws only this view; SwiftUI hands over just the pose. The view reads the
/// pointer itself and eases the eyes towards it.
public struct MelyCharacter: NSViewRepresentable {
    /// Where the eyes go.
    public enum Look: Equatable, Sendable {
        /// After the pointer, wherever it is on screen.
        case pointer
        /// Here and there on their own (the little Melys of the session list).
        case wander
        /// Straight ahead.
        case ahead
    }

    let pose: CharacterPose
    let look: Look
    /// Body colour; nil is Mely's own cream.
    let tint: CGColor?
    /// Reacts to clicks (the big Mely); elsewhere clicks go to what is under it.
    let interactive: Bool

    public init(pose: CharacterPose, look: Look = .pointer, tint: CGColor? = nil, interactive: Bool = false) {
        self.pose = pose
        self.look = look
        self.tint = tint
        self.interactive = interactive
    }

    public func makeNSView(context: Context) -> MelyCharacterView {
        let view = MelyCharacterView()
        view.interactive = interactive
        return view
    }

    public func updateNSView(_ view: MelyCharacterView, context: Context) {
        if view.pose != pose { view.pose = pose }
        if view.look != look { view.look = look }
        if view.tint != tint { view.tint = tint }
        let appearance = context.environment.characterAppearance
        if view.character != appearance { view.character = appearance; view.needsDisplay = true }
        view.drag = interactive ? context.environment.characterDrag : nil
    }
}

/// Redraws while it is in a visible window and stops otherwise: 60 times a second while
/// the eyes travel, 12 once they rest.
public final class MelyCharacterView: NSView {
    var pose: CharacterPose = .idle {
        didSet {
            updateLabel()
            guard pose != oldValue else { return }
            // A new pose moves (a hop when glad): smooth frames while it settles in.
            poseChangedAt = Date.timeIntervalSinceReferenceDate
            if !isFast { schedule(fast: true) }
        }
    }
    /// When the pose last changed; the first `poseSettle` seconds after it run at 60 fps.
    private var poseChangedAt: TimeInterval = 0
    private static let poseSettle: TimeInterval = 2
    var look: MelyCharacter.Look = .pointer
    var tint: CGColor?
    var character = CharacterAppearance() { didSet { updateLabel() } }
    var interactive = false
    /// Pulled out past a few points, a click becomes carrying Mely away.
    var drag: CharacterDrag?
    private var pressedAt: CGPoint?
    private var dragging = false
    private var timer: Timer?
    /// A click: a squash and a hop; many quick ones make it dizzy.
    private var emote: CharacterEmote?
    private var clicks: [TimeInterval] = []
    /// Asleep, it wakes while the pointer is close.
    private var pointerNear = false
    /// Eyes now and where they head, -1…1.
    private var gaze = CGPoint.zero
    private var target = CGPoint.zero
    private var lastTick: TimeInterval = 0
    private var nextWander: TimeInterval = 0

    override public var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// "Mely (Лисёнок): Работает"; just "Mely: …" in its own look.
    private func updateLabel() {
        let title = character.lookId == BuiltInLooks.mely.id ? nil : CharacterLookTitles.title(character.lookId)
        setAccessibilityLabel("Mely" + (title.map { " (\($0))" } ?? "") + ": \(pose.title)")
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        schedule(fast: false)
    }

    /// 60 ticks a second while the eyes travel, 12 once they rest (breathing needs no more).
    private func schedule(fast: Bool) {
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        let t = Timer(timeInterval: fast ? 1.0 / 60 : 1.0 / 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = fast ? 0.004 : 0.01
        RunLoop.main.add(t, forMode: .common)
        timer = t
        isFast = fast
    }

    private var isFast = false
    private var restingSince: TimeInterval = 0
    /// When the next wink or confetti may come (task 7.5); 0 until the first tick.
    private var nextQuirk: TimeInterval = 0

    /// Now and then, while nothing needs the user: a wink, or confetti on a special day.
    private func quirkIfDue(now: TimeInterval) {
        // The big Mely and the notch's one; not the session list's small ones.
        guard look == .pointer, emote == nil else { return }
        if nextQuirk == 0 { nextQuirk = now + .random(in: CharacterQuirks.interval); return }
        guard now >= nextQuirk else { return }
        nextQuirk = now + .random(in: CharacterQuirks.interval)
        guard CharacterQuirks.allowed(in: pose), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let birthday = CharacterQuirks.birthday(from: UserDefaults.standard.string(forKey: CharacterQuirks.birthdayKey))
        switch CharacterQuirks.pick(on: Date(), birthday: birthday, roll: .random(in: 0..<1)) {
        case .wink: emote = CharacterEmote(kind: .wink, start: now, duration: 0.7)
        case .party: emote = CharacterEmote(kind: .party, start: now, duration: 2.4)
        }
    }

    private func tick() {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return }
        let now = Date.timeIntervalSinceReferenceDate
        let dt = min(0.1, max(0, now - lastTick))
        lastTick = now
        target = aim(now: now, window: window)
        // Exponential ease, frame-rate independent: most of the way in about a third of a second.
        let k = 1 - pow(0.0025, dt)
        gaze.x += (target.x - gaze.x) * k
        gaze.y += (target.y - gaze.y) * k
        needsDisplay = true
        quirkIfDue(now: now)
        // Eyes on the move or a reaction playing: smooth frames.
        let travelling = abs(target.x - gaze.x) + abs(target.y - gaze.y) > 0.01 || emote?.isRunning(now) == true
            || now - poseChangedAt < Self.poseSettle
        if travelling {
            restingSince = now
            if !isFast { schedule(fast: true) }
        } else if isFast, now - restingSince > 0.3 {
            schedule(fast: false)
        }
    }

    /// The pointer seen from the character's centre, softly saturating far away.
    private func aim(now: TimeInterval, window: NSWindow) -> CGPoint {
        switch look {
        case .ahead:
            return .zero
        case .wander:
            if now >= nextWander {
                nextWander = now + Double.random(in: 0.6...2.2)
                return CGPoint(x: .random(in: -0.85...0.85), y: .random(in: -0.5...0.45))
            }
            return target
        case .pointer:
            let center = window.convertPoint(toScreen: convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil))
            let mouse = NSEvent.mouseLocation
            pointerNear = hypot(mouse.x - center.x, mouse.y - center.y) < max(60, bounds.width * 1.5)
            // Screen y goes up, the drawing's y goes down.
            return CGPoint(x: tanh((mouse.x - center.x) / 260), y: tanh((center.y - mouse.y) / 200))
        }
    }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        interactive ? super.hitTest(point) : nil
    }

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { interactive }

    override public func mouseDown(with event: NSEvent) {
        guard interactive else { return super.mouseDown(with: event) }
        pressedAt = NSEvent.mouseLocation
        dragging = false
        MelyHaptics.tap()
        poke()
    }

    override public func mouseDragged(with event: NSEvent) {
        guard interactive, let drag, let start = pressedAt else { return super.mouseDragged(with: event) }
        let mouse = NSEvent.mouseLocation
        if !dragging {
            guard hypot(mouse.x - start.x, mouse.y - start.y) > 4 else { return }
            dragging = true
            drag.began(mouse)
        }
        drag.moved(mouse)
    }

    override public func mouseUp(with event: NSEvent) {
        guard interactive else { return super.mouseUp(with: event) }
        if dragging { drag?.ended(NSEvent.mouseLocation) }
        dragging = false
        pressedAt = nil
    }

    /// A click: a squash and a hop; five quick ones make it dizzy.
    public func poke() {
        let now = Date.timeIntervalSinceReferenceDate
        clicks = clicks.filter { now - $0 < 2 } + [now]
        emote = CharacterEmote.after(clicks: clicks.count, now: now)
        needsDisplay = true
    }

    override public func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let now = Date.timeIntervalSinceReferenceDate
        if let e = emote, !e.isRunning(now) { emote = nil }
        // Asleep with the pointer close: awake for as long as it stays.
        let shown = pose == .sleeping && pointerNear ? .idle : pose
        CharacterDrawing(appearance: character, pose: shown, gaze: look == .ahead ? nil : gaze,
                         t: now, tint: tint, emote: emote)
            .draw(in: cg, size: bounds.size)
    }
}

@MainActor enum CharacterLookTitles {
    static func title(_ id: String) -> String? {
        BuiltInLooks.all.first { $0.id == id }?.title
    }
}

/// A one-off reaction to clicks.
struct CharacterEmote: Equatable {
    enum Kind { case poke, dizzy, wink, party }
    let kind: Kind
    let start: TimeInterval
    let duration: TimeInterval

    /// Five clicks within two seconds make it dizzy; fewer, a poke.
    static func after(clicks: Int, now: TimeInterval) -> CharacterEmote {
        clicks >= 5 ? CharacterEmote(kind: .dizzy, start: now, duration: 2.6) : CharacterEmote(kind: .poke, start: now, duration: 0.6)
    }

    func progress(_ t: TimeInterval) -> Double { max(0, min(1, (t - start) / duration)) }
    func isRunning(_ t: TimeInterval) -> Bool { t - start < duration }
}

/// A reaction caught in a still frame (snapshots).
public enum Reaction: Sendable {
    case poke, wink, party
    var kind: CharacterEmote.Kind { switch self { case .poke: .poke; case .wink: .wink; case .party: .party } }
    var duration: TimeInterval { switch self { case .poke: 0.6; case .wink: 0.7; case .party: 2.4 } }
}

/// One still frame of Mely at a given moment: for snapshots and previews.
public struct MelyCharacterFrame: View {
    let pose: CharacterPose
    let gaze: CGPoint?
    let time: TimeInterval
    let tint: CGColor?
    /// nil: the one in the environment.
    let appearance: CharacterAppearance?
    let dizzy: Bool
    let reaction: Reaction?
    @Environment(\.characterAppearance) private var current

    public init(pose: CharacterPose, gaze: CGPoint? = nil, time: TimeInterval = 0.6, tint: CGColor? = nil,
                appearance: CharacterAppearance? = nil, dizzy: Bool = false, reaction: Reaction? = nil) {
        self.dizzy = dizzy
        self.reaction = reaction
        self.pose = pose
        self.gaze = gaze
        self.time = time
        self.tint = tint
        self.appearance = appearance
    }

    public var body: some View {
        Canvas { ctx, size in
            let drawing = CharacterDrawing(appearance: appearance ?? current, pose: pose, gaze: gaze, t: time, tint: tint,
                                           emote: dizzy ? CharacterEmote(kind: .dizzy, start: 0, duration: 99)
                                               : reaction.map { CharacterEmote(kind: $0.kind, start: time - 0.35 * $0.duration, duration: $0.duration) })
            ctx.withCGContext { cg in MainActor.assumeIsolated { drawing.draw(in: cg, size: size) } }
        }
    }
}

/// One frame of the character: a pure function of look, pose, gaze and time, in a
/// top-down CGContext. Canvas characters share the face, the poses and the wardrobe;
/// each species draws its body around them (task 6.2).
struct CharacterDrawing {
    let appearance: CharacterAppearance
    var pose: CharacterPose
    let gaze: CGPoint?
    let t: TimeInterval
    var tint: CGColor? = nil
    var emote: CharacterEmote? = nil

    static let ink = rgb(0.24, 0.16, 0.15)
    static let blush = rgb(1.0, 0.55, 0.55)

    @MainActor func draw(in cg: CGContext, size: CGSize) {
        // A poke shows the happy face for its moment.
        if emote?.kind == .poke || emote?.kind == .party, pose != .happy {
            var glad = self
            glad.pose = .happy
            return glad.draw(in: cg, size: size)
        }
        let side = min(size.width, size.height)
        var r = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        let pen = Pen(cg)
        if appearance.lookId == BuiltInLooks.minimal.id {
            MinimalDrawing(pose: pose, t: t).draw(pen, r)
            return
        }
        let species = SpeciesCatalog.named(appearance.lookId)
        let paint = SpeciesPaint(values: appearance.values, tint: tint)
        let hidden = species.hiddenSlots(pose)
        let outfit = appearance.outfit.filter { !hidden.contains($0.key) }
        // A hat needs room above the head: the character steps down a little.
        if outfit[.head] != nil {
            let k = 0.8
            r = CGRect(x: r.midX - side * k / 2, y: r.maxY - side * k, width: side * k, height: side * k)
        }
        let move = motion()
        let pivot = CGPoint(x: r.midX, y: r.maxY - r.height * 0.05)
        let body = BodyContext(pen: pen, r: r, pose: pose, t: t, paint: paint, outfit: outfit)
        let anchors = species.anchors
        pen.saving {
            // Squash, stretch and tilt around the bottom centre, so it stays on the ground.
            cg.translateBy(x: pivot.x + move.dx * r.width, y: pivot.y + move.dy * r.height)
            cg.rotate(by: move.tilt * .pi / 180)
            cg.scaleBy(x: move.sx, y: move.sy)
            cg.translateBy(x: -pivot.x, y: -pivot.y)
            if let cape = outfit[.back] { AccessoryDrawing.draw(cape, pen, r, anchors, t: t) }
            species.drawBack(body)
            species.drawBody(body)
            if paint.cheeks {
                // Rosier when happy or dancing, pale when sad.
                let strength = pose == .happy || pose == .dancing ? 0.75 : pose == .sad || pose == .scared ? 0.25 : 0.5
                for x in anchors.cheekX {
                    pen.fill(Path(ellipseIn: rect(r, x - 0.07, anchors.cheekY, 0.14, 0.07)), Self.blush.copy(alpha: strength)!)
                }
            }
            drawFace(pen, r, beak: species.hasBeak)
            species.drawFront(body)
            for slot in [AccessorySlot.neck, .eyes, .head, .held] {
                if let item = outfit[slot] { AccessoryDrawing.draw(item, pen, r, anchors, t: t) }
            }
        }
        if dizzy { drawDizzyStars(pen, r) } else { drawExtras(pen, r) }
        if let emote, emote.kind == .party { drawConfetti(pen, r, emote.progress(t)) }
        // A poke tickles (task 7.5): two little hearts float up over the head.
        if let emote, emote.kind == .poke, r.width >= 40 {
            let p = emote.progress(t)
            for (k, x) in [0.16, 0.84].enumerated() {
                let rise = p - Double(k) * 0.15
                guard rise > 0 else { continue }
                pen.text("♥", size: r.width * (0.12 - 0.02 * Double(k)), weight: .bold,
                         color: Self.rgb(1, 0.55, 0.65, max(0, 1 - rise)),
                         at: point(r, x, 0.3 - 0.22 * rise))
            }
        }
    }

    /// A burst of confetti falling around (task 7.5): a special day.
    private func drawConfetti(_ pen: Pen, _ r: CGRect, _ p: Double) {
        let colors = [Self.rgb(1, 0.85, 0.3), Self.rgb(0.55, 0.9, 0.7), Self.rgb(1, 0.6, 0.68),
                      Self.rgb(0.6, 0.72, 1), Self.rgb(0.78, 0.65, 1)]
        let fade = p < 0.75 ? 1 : (1 - p) / 0.25
        for k in 0..<14 {
            let seed = Double(k) * 1.618
            let x0 = 0.5 + 0.45 * sin(seed * 2.3)
            let fall = p * (0.7 + 0.3 * sin(seed))
            let x = x0 + 0.06 * sin(t * 5 + seed)
            let y = -0.05 + fall * 1.0 + 0.04 * cos(seed * 3)
            let angle = t * 6 + seed
            pen.saving {
                let c = point(r, x, y)
                pen.cg.translateBy(x: c.x, y: c.y)
                pen.cg.rotate(by: angle)
                let w = r.width * 0.05, h = r.width * 0.025
                pen.fill(Path(CGRect(x: -w / 2, y: -h / 2, width: w, height: h)),
                         colors[k % colors.count].copy(alpha: fade)!)
            }
        }
    }

    // MARK: Motion

    private struct Motion { var dx = 0.0, dy = 0.0, sx = 1.0, sy = 1.0, tilt = 0.0 }

    private func motion() -> Motion {
        var m = Motion()
        // Leans a little towards the pointer, so a glance reads even when tiny.
        if pose != .sleeping { m.tilt = 3.3 * clampedGaze.x }
        let breath = sin(t * 2 * .pi / (pose == .sleeping ? 4.5 : 3.2))
        m.sy = 1 + 0.03 * breath * (pose == .sleeping ? 1.4 : 1)
        m.sx = 1 - 0.015 * breath
        switch pose {
        case .happy:
            let hop = abs(sin(t * 2 * .pi * 0.9))
            m.dy = -0.08 * hop
            m.sy *= 1 + 0.05 * hop
            m.sx *= 1 - 0.03 * hop
        case .dancing:
            m.tilt += 7 * sin(t * 2 * .pi * 0.95)
            m.dy = -0.03 * abs(sin(t * 2 * .pi * 1.9))
        case .worried:
            m.dx = 0.006 * sin(t * 38)
        case .scared:
            m.dx = 0.012 * sin(t * 55)
            m.sx *= 1.04
            m.sy *= 1.05
        case .curious:
            m.tilt += 8 + 2 * sin(t * 1.5)
        case .sad:
            m.sy *= 0.95
            m.dy = 0.02
        case .working:
            m.tilt += 1.5 * sin(t * 2 * .pi * 0.5)
        case .idle, .sleeping:
            break
        }
        if let emote {
            let p = emote.progress(t)
            switch emote.kind {
            case .poke:
                // Squashed by the click, then a little hop.
                let squash = sin(min(1, p * 3) * .pi)
                m.sy *= 1 - 0.14 * squash
                m.sx *= 1 + 0.1 * squash
                m.dy -= 0.1 * sin(max(0, p * 1.5 - 0.5) * .pi)
            case .dizzy:
                m.tilt += 11 * sin(t * 9)
                m.dx += 0.02 * sin(t * 4.5)
            case .wink:
                // A slight lean towards the winking eye.
                m.tilt += 5 * sin(p * .pi)
            case .party:
                // Two hops of joy.
                m.dy -= 0.07 * abs(sin(p * 2 * .pi))
            }
        }
        return m
    }

    private var dizzy: Bool { emote?.kind == .dizzy }

    /// Stars circling over the head.
    private func drawDizzyStars(_ pen: Pen, _ r: CGRect) {
        for k in 0..<3 {
            let a = t * 4 + Double(k) * 2 * .pi / 3
            pen.text("✦", size: r.width * 0.15, weight: .bold, color: Self.rgb(1, 0.85, 0.3, 0.6 + 0.4 * sin(a)),
                     at: point(r, 0.5 + 0.3 * cos(a), 0.14 + 0.06 * sin(a)))
        }
    }

    // MARK: Face

    private func drawFace(_ pen: Pen, _ r: CGRect, beak: Bool) {
        let look = lookOffset()
        let lw = r.width * 0.035
        for (i, x) in [0.35, 0.65].enumerated() {
            let cx = x + look.x, cy = 0.575 + look.y
            if dizzy {
                // Spinning spirals.
                var spiral = Path()
                let turns = 2.2, steps = 28
                for k in 0...steps {
                    let f = Double(k) / Double(steps)
                    let a = f * turns * 2 * .pi + t * 8 * (i == 0 ? 1 : -1)
                    let rr = 0.06 * f
                    let pt = point(r, x + rr * cos(a), 0.575 + rr * sin(a))
                    if k == 0 { spiral.move(to: pt) } else { spiral.addLine(to: pt) }
                }
                pen.stroke(spiral, Self.ink, width: lw * 0.8)
                continue
            }
            // A wink: the right eye closes in a happy arc for a moment.
            if emote?.kind == .wink, i == 1, pose != .sleeping {
                var arc = Path()
                arc.move(to: point(r, cx - 0.055, cy + 0.01))
                arc.addQuadCurve(to: point(r, cx + 0.055, cy + 0.01), control: point(r, cx, cy - 0.06))
                pen.stroke(arc, Self.ink, width: lw)
                continue
            }
            switch eyes {
            case .open(let scale):
                let w = 0.11 * scale, h = 0.15 * scale * blinkOpenness
                pen.fill(Path(ellipseIn: rect(r, cx - w / 2, cy - h / 2, w, max(h, 0.012))), Self.ink)
                if blinkOpenness > 0.5 {
                    pen.fill(Path(ellipseIn: rect(r, cx - 0.018, cy - 0.05 * scale, 0.035, 0.035)), Self.rgb(1, 1, 1, 0.9))
                }
            case .focused:
                // Half-closed: the top lid is flat.
                pen.saving {
                    pen.cg.clip(to: rect(r, cx - 0.07, cy - 0.025, 0.14, 0.2))
                    pen.fill(Path(ellipseIn: rect(r, cx - 0.055, cy - 0.05, 0.11, 0.12)), Self.ink)
                }
            case .happy:
                var p = Path()
                p.move(to: point(r, cx - 0.055, cy + 0.02))
                p.addQuadCurve(to: point(r, cx + 0.055, cy + 0.02), control: point(r, cx, cy - 0.07))
                pen.stroke(p, Self.ink, width: lw)
            case .closed:
                var p = Path()
                p.move(to: point(r, cx - 0.05, cy))
                p.addQuadCurve(to: point(r, cx + 0.05, cy), control: point(r, cx, cy + 0.05))
                pen.stroke(p, Self.ink, width: lw)
            }
            // Brows tell worry and sadness: outer end low, inner end (towards the nose) high.
            if pose == .worried || pose == .sad {
                let outer = i == 0 ? -0.06 : 0.06
                var b = Path()
                b.move(to: point(r, cx + outer, cy - 0.11))
                b.addLine(to: point(r, cx - outer * 0.2, cy - 0.16))
                pen.stroke(b, Self.ink.copy(alpha: 0.8)!, width: lw * 0.8)
            }
        }
        if dizzy, !beak {
            var wave = Path()
            wave.move(to: point(r, 0.43, 0.72))
            wave.addCurve(to: point(r, 0.57, 0.72), control1: point(r, 0.47, 0.68), control2: point(r, 0.53, 0.76))
            pen.stroke(wave, Self.ink, width: lw)
        } else if !beak {
            drawMouth(pen, r, lw)
        }
    }

    private enum Eyes { case open(Double), focused, happy, closed }

    private var eyes: Eyes {
        switch pose {
        case .happy: .happy
        case .sleeping: .closed
        case .working: .focused
        case .scared: .open(1.3)
        case .curious: .open(1.1)
        case .sad, .worried: .open(0.9)
        case .idle, .dancing: .open(1)
        }
    }

    /// 0 closed … 1 open: a quick blink every few seconds, sometimes twice.
    private var blinkOpenness: Double {
        let period = 4.3
        let phase = t.truncatingRemainder(dividingBy: period)
        let second = Int(t / period) % 3 == 0 && phase > 0.25 && phase < 0.37
        return phase < 0.12 || second ? 0.08 : 1
    }

    /// Eyes follow the pointer in every pose but sleep, far enough to see at 26 pt.
    /// Working with the pointer far away, they glance around on their own.
    private func lookOffset() -> CGPoint {
        guard pose != .sleeping else { return .zero }
        let g = clampedGaze
        let far = gaze == nil || (abs(g.x) > 0.95 && abs(g.y) > 0.9)
        if pose == .working && far { return CGPoint(x: 0.05 * sin(t * 0.9), y: -0.02) }
        // Sad eyes stay a little low whatever they look at.
        return CGPoint(x: 0.057 * g.x, y: 0.041 * g.y + (pose == .sad ? 0.02 : 0))
    }

    private var clampedGaze: CGPoint {
        guard let gaze else { return .zero }
        return CGPoint(x: max(-1, min(1, gaze.x)), y: max(-1, min(1, gaze.y)))
    }

    private func drawMouth(_ pen: Pen, _ r: CGRect, _ lw: CGFloat) {
        var p = Path()
        switch pose {
        case .happy, .dancing:
            // Open smile.
            p.move(to: point(r, 0.43, 0.7))
            p.addQuadCurve(to: point(r, 0.57, 0.7), control: point(r, 0.5, 0.8))
            p.closeSubpath()
            pen.fill(p, Self.ink)
            return
        case .scared, .curious:
            pen.stroke(Path(ellipseIn: rect(r, 0.47, 0.69, 0.06, pose == .scared ? 0.07 : 0.05)), Self.ink, width: lw * 0.9)
            return
        case .sad:
            p.move(to: point(r, 0.44, 0.75))
            p.addQuadCurve(to: point(r, 0.56, 0.75), control: point(r, 0.5, 0.69))
        case .worried:
            p.move(to: point(r, 0.44, 0.73))
            p.addCurve(to: point(r, 0.56, 0.73), control1: point(r, 0.48, 0.7), control2: point(r, 0.52, 0.76))
        case .working:
            p.move(to: point(r, 0.46, 0.725))
            p.addLine(to: point(r, 0.54, 0.725))
        case .sleeping:
            pen.fill(Path(ellipseIn: rect(r, 0.48, 0.71, 0.04, 0.035)), Self.ink.copy(alpha: 0.8)!)
            return
        case .idle:
            p = MelyLogo.smile(in: r)
        }
        pen.stroke(p, Self.ink, width: lw)
    }

    // MARK: Extras

    private func drawExtras(_ pen: Pen, _ r: CGRect) {
        let s = r.width
        let green = Self.rgb(0.3, 0.8, 0.45), water = Self.rgb(0.55, 0.8, 1.0)
        switch pose {
        case .sleeping:
            // Two z's drifting up and fading.
            for k in 0..<2 {
                let phase = ((t / 2.4) + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                pen.text("z", size: s * (0.16 + 0.06 * Double(k)), weight: .bold, color: Self.rgb(1, 1, 1, 0.85 * (1 - phase)),
                         at: point(r, 0.8 + 0.08 * phase, 0.3 - 0.25 * phase))
            }
        case .dancing:
            for k in 0..<2 {
                let phase = ((t / 1.8) + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                pen.text(k == 0 ? "♪" : "♫", size: s * 0.2, weight: .regular, color: green.copy(alpha: 1 - phase)!,
                         at: point(r, k == 0 ? 0.1 - 0.05 * phase : 0.9 + 0.05 * phase, 0.35 - 0.3 * phase))
            }
        case .worried:
            // A sweat drop sliding down the side.
            let y = 0.32 + 0.12 * (t / 1.6).truncatingRemainder(dividingBy: 1)
            var drop = Path()
            drop.move(to: point(r, 0.84, y - 0.06))
            drop.addQuadCurve(to: point(r, 0.84, y + 0.04), control: point(r, 0.9, y + 0.02))
            drop.addQuadCurve(to: point(r, 0.84, y - 0.06), control: point(r, 0.78, y + 0.02))
            pen.fill(drop, water)
        case .curious:
            pen.text("?", size: s * 0.26, weight: .heavy, color: Self.rgb(1.0, 0.75, 0.3), at: point(r, 0.88, 0.22 + 0.02 * sin(t * 3)))
        case .sad:
            let y = 0.66 + 0.1 * (t / 2).truncatingRemainder(dividingBy: 1)
            pen.fill(Path(ellipseIn: rect(r, 0.285, y, 0.04, 0.06)), water.copy(alpha: 0.9)!)
        case .happy:
            for (k, spot) in [(0.12, 0.3), (0.9, 0.38), (0.82, 0.12)].enumerated() {
                let twinkle = (sin(t * 5 + Double(k) * 2) + 1) / 2
                pen.text("✦", size: s * 0.14, weight: .regular, color: Self.rgb(1.0, 0.85, 0.3, twinkle), at: point(r, spot.0, spot.1))
            }
        case .working:
            // Three dots taking turns over the head.
            for k in 0..<3 {
                let on = Int(t * 3) % 3 == k
                pen.fill(Path(ellipseIn: rect(r, 0.38 + Double(k) * 0.1, 0.06, 0.06, 0.06)), Self.rgb(1, 1, 1, on ? 0.95 : 0.35))
            }
        case .scared:
            pen.text("!", size: s * 0.26, weight: .heavy, color: Self.rgb(1.0, 0.45, 0.4), at: point(r, 0.88, 0.2))
        case .idle:
            break
        }
    }

    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: Geometry in a unit square

func point(_ r: CGRect, _ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
}

func rect(_ r: CGRect, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    CGRect(x: r.minX + x * r.width, y: r.minY + y * r.height, width: w * r.width, height: h * r.height)
}

/// The few drawing operations Mely needs, over a top-down CGContext.
struct Pen {
    let cg: CGContext
    init(_ cg: CGContext) { self.cg = cg }

    func saving(_ body: () -> Void) {
        cg.saveGState()
        body()
        cg.restoreGState()
    }

    func fill(_ path: Path, _ color: CGColor) {
        cg.addPath(path.cgPath)
        cg.setFillColor(color)
        cg.fillPath()
    }

    func fill(_ path: Path, gradient colors: [CGColor], from: CGPoint, to: CGPoint) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) else { return }
        saving {
            cg.addPath(path.cgPath)
            cg.clip()
            cg.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    func stroke(_ path: Path, _ color: CGColor, width: CGFloat) {
        cg.addPath(path.cgPath)
        cg.setStrokeColor(color)
        cg.setLineWidth(width)
        cg.setLineCap(.round)
        cg.strokePath()
    }

    /// Text centred on `at`, drawn through AppKit on the same (flipped) context.
    func text(_ string: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, at center: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                         .foregroundColor: NSColor(cgColor: color) ?? .white]
        let text = NSAttributedString(string: string, attributes: attributes)
        let bounds = text.size()
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        text.draw(at: CGPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
        NSGraphicsContext.current = previous
    }
}
