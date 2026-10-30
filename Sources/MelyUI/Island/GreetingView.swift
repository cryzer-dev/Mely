import SwiftUI
import MelyCore

/// The launch greeting (task 7.2), Mely's own: the notch opens, Mely drops in from it
/// with a trail, lands with a squash, sparkles burst around, «Привет! Я Mely» comes in,
/// then the island folds. Two seconds; with Reduce Motion, a plain fade.
public struct GreetingView: View {
    /// When the greeting started; the animation is a pure function of the time since.
    let start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public static let duration: TimeInterval = 2.0

    public init(start: Date) {
        self.start = start
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: false)) { context in
            let t = context.date.timeIntervalSince(start)
            let frame = GreetingTimeline.frame(at: reduceMotion ? max(t, 1.0) : t)
            HStack(spacing: 14) {
                ZStack {
                    // The trail of the fall.
                    Canvas { ctx, size in
                        GreetingTimeline.drawTrail(ctx, size: size, progress: frame.trail)
                        GreetingTimeline.drawSparkles(ctx, size: size, progress: frame.sparkles)
                    }
                    .frame(width: 120, height: 110)
                    MelyCharacterFrame(pose: frame.pose, gaze: CGPoint(x: frame.look, y: 0.1), time: t)
                        .frame(width: 70, height: 70)
                        .scaleEffect(x: frame.scaleX, y: frame.scaleY, anchor: .bottom)
                        .offset(y: frame.dropY)
                        .opacity(frame.mely)
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Привет! Я Mely")
                        .font(.system(size: MelyType.display, weight: .bold, design: .rounded))
                    Text("Живу в челке и присматриваю за твоими агентами")
                        .font(.system(size: MelyType.body))
                        .foregroundStyle(.white.opacity(MelyInk.secondary))
                }
                .foregroundStyle(.white)
                .opacity(frame.text)
                .offset(x: (1 - frame.text) * 10)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Привет! Я Mely")
    }
}

/// The greeting's choreography, separate from drawing so it can be checked frame by frame.
public enum GreetingTimeline {
    public struct Frame: Equatable {
        public var pose: CharacterPose
        /// Points above its resting place (negative: up).
        public var dropY: CGFloat
        public var scaleX: CGFloat
        public var scaleY: CGFloat
        public var mely: Double
        public var trail: Double
        public var sparkles: Double
        public var text: Double
        /// Gaze: down the fall, then at the words.
        public var look: CGFloat
    }

    static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { max(0, min(1, (t - a) / (b - a))) }
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func back(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    public static func frame(at t: Double) -> Frame {
        // 0.16–0.50: the fall, overshooting a little into the landing.
        let fall = seg(t, 0.16, 0.50)
        let dropY = CGFloat(-90 * (1 - back(fall)))
        // 0.50–0.72: the squash and its spring back.
        let land = seg(t, 0.50, 0.72)
        let squash = sin(land * .pi) * (1 - land * 0.4)
        // 1.16–1.40: a little hop of joy.
        let hop = seg(t, 1.16, 1.40)
        let hopY = CGFloat(-10 * sin(hop * .pi))
        return Frame(
            pose: t < 0.50 ? .curious : .happy,
            dropY: dropY + hopY,
            scaleX: 1 + CGFloat(0.16 * squash),
            scaleY: 1 - CGFloat(0.18 * squash),
            mely: seg(t, 0.12, 0.24),
            trail: t < 0.16 ? 0 : seg(t, 0.16, 0.64),
            sparkles: seg(t, 0.50, 1.12),
            text: easeOut(seg(t, 0.68, 1.0)),
            look: t < 0.72 ? 0 : CGFloat(0.6 * easeOut(seg(t, 0.72, 0.96))))
    }

    /// Thin falling streaks behind Mely, fading as it lands.
    static func drawTrail(_ ctx: GraphicsContext, size: CGSize, progress: Double) {
        guard progress > 0, progress < 1 else { return }
        let fade = 1 - progress
        for i in 0..<9 {
            let x = size.width / 2 + CGFloat(i - 4) * 7 + CGFloat((i * 37) % 5)
            let len = CGFloat(18 + (i * 13) % 22) * fade
            let y = size.height * 0.15 + CGFloat(progress) * size.height * 0.45 - CGFloat((i * 17) % 20)
            var line = Path()
            line.move(to: CGPoint(x: x, y: y - len))
            line.addLine(to: CGPoint(x: x, y: y))
            ctx.stroke(line, with: .color(.white.opacity(0.35 * fade)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

    /// A ring of little stars bursting out from the landing.
    static func drawSparkles(_ ctx: GraphicsContext, size: CGSize, progress: Double) {
        guard progress > 0, progress < 1 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height * 0.62)
        let colors: [Color] = [Color(red: 1, green: 0.85, blue: 0.4), Color(red: 0.55, green: 0.9, blue: 0.7),
                               Color(red: 1, green: 0.62, blue: 0.68), .white]
        let radius = 20 + 34 * easeOut(progress)
        let alpha = progress < 0.6 ? 1 : (1 - progress) / 0.4
        for i in 0..<10 {
            let angle = Double(i) / 10 * 2 * .pi - .pi / 2 + 0.3
            let r = radius * (i.isMultiple(of: 2) ? 1 : 0.8)
            let p = CGPoint(x: center.x + CGFloat(cos(angle) * r), y: center.y + CGFloat(sin(angle) * r * 0.75))
            let s = CGFloat(i.isMultiple(of: 2) ? 3.2 : 2.2) * CGFloat(1 - progress * 0.5)
            var star = Path()
            star.move(to: CGPoint(x: p.x, y: p.y - s * 1.6))
            star.addQuadCurve(to: CGPoint(x: p.x + s * 1.6, y: p.y), control: p)
            star.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s * 1.6), control: p)
            star.addQuadCurve(to: CGPoint(x: p.x - s * 1.6, y: p.y), control: p)
            star.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s * 1.6), control: p)
            ctx.fill(star, with: .color(colors[i % colors.count].opacity(alpha)))
        }
    }
}
