import SwiftUI
import MelyCore

/// The big Mely of the expanded island, left of the content, on a soft glow in the
/// colour of its mood.
public struct MelyStage: View {
    let pose: CharacterPose
    let size: CGFloat
    @Environment(\.characterDrag) private var drag

    /// The big Mely's size in the open island.
    public static let defaultSize: CGFloat = 80
    /// The left column of the open island: the stage, and what hangs under it.
    public static let columnWidth: CGFloat = (defaultSize * 1.25).rounded()

    public init(pose: CharacterPose, size: CGFloat = MelyStage.defaultSize) {
        self.pose = pose
        self.size = size
    }

    public var body: some View {
        if let drag, drag.isAway {
            away(drag)
        } else {
            stage
        }
    }

    /// Mely is out on the desktop: its spot offers to call it back.
    private func away(_ drag: CharacterDrag) -> some View {
        Button(action: drag.callHome) {
            VStack(spacing: 4) {
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .overlay(Image(systemName: "house.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.6)))
                    .frame(width: size * 0.8, height: size * 0.8)
                Text("на столе").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .frame(width: size * 1.25, height: size * 1.4)
        .help("Вернуть Mely в челку")
        .accessibilityLabel("Mely на рабочем столе. Вернуть в челку")
    }

    private var stage: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Self.glow(pose), .clear], center: .center,
                                     startRadius: 0, endRadius: size * 0.75))
                .frame(width: size * 1.7, height: size * 1.7)
                .blur(radius: 6)
                .opacity(pose == .idle || pose == .sleeping ? 0.25 : 0.55)
                .animation(.easeInOut(duration: 0.4), value: pose)
            // Click it: it reacts; five quick clicks make it dizzy. Pull it out: onto a
            // window to ask about it, anywhere else to leave it on the desktop.
            MelyCharacter(pose: pose, interactive: true)
                .frame(width: size, height: size)
        }
        .frame(width: size * 1.25, height: size * 1.4)
        .accessibilityElement(children: .combine)
    }

    static func glow(_ pose: CharacterPose) -> Color {
        switch pose {
        case .working: Color(red: 0.23, green: 0.62, blue: 1.0)
        case .worried: Color(red: 0.96, green: 0.65, blue: 0.14)
        case .curious: Color(red: 0.65, green: 0.55, blue: 0.98)
        case .happy: Color(red: 0.2, green: 0.83, blue: 0.6)
        case .scared: Color(red: 0.96, green: 0.31, blue: 0.37)
        case .sad: Color(red: 0.96, green: 0.62, blue: 0.04)
        case .dancing: Color(red: 0.93, green: 0.36, blue: 0.6)
        case .idle, .sleeping: Color(white: 0.7)
        }
    }
}

/// A session's own little Mely, in a colour picked from its project name, so each
/// project keeps its colour.
public struct SessionMely: View {
    let session: ClaudeSession
    var size: CGFloat = 26

    public init(session: ClaudeSession, size: CGFloat = 26) {
        self.session = session
        self.size = size
    }

    public var body: some View {
        MelyCharacter(pose: CharacterMood.pose(for: session.state), look: .wander,
                      tint: SessionPalette.color(for: session.projectName))
            .frame(width: size, height: size)
    }
}

/// Pastel body colours for the session Melys.
public enum SessionPalette {
    static let colors: [CGColor] = [
        (1.0, 0.62, 0.68), (0.55, 0.85, 0.72), (0.62, 0.72, 1.0), (1.0, 0.78, 0.5),
        (0.78, 0.65, 1.0), (0.5, 0.82, 0.95), (1.0, 0.88, 0.45), (0.95, 0.6, 0.9),
    ].map { CGColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) }

    /// Stable across launches (no `hashValue`, which is seeded per process).
    public static func color(for name: String) -> CGColor {
        // FNV-1a: short names still spread over the palette.
        let hash = name.unicodeScalars.reduce(UInt32(2_166_136_261)) { ($0 ^ $1.value) &* 16_777_619 }
        return colors[Int(hash % UInt32(colors.count))]
    }
}
