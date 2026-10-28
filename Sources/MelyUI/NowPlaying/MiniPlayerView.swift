import SwiftUI
import AppKit
import MelyCore

/// The "Музыка" tab: what plays, where, how far, with controls.
public struct MiniPlayerView: View {
    let model: NowPlayingModel
    /// The bell by the source app: its new tracks with or without a preview.
    let peeks: NowPlayingPeeks?
    let send: (MediaCommand) -> Void
    /// Jumps to a position (seconds); nil: the bar only shows it.
    let seek: ((TimeInterval) -> Void)?
    let openSource: (String) -> Void

    public init(model: NowPlayingModel, peeks: NowPlayingPeeks? = nil, send: @escaping (MediaCommand) -> Void,
                seek: ((TimeInterval) -> Void)? = nil, openSource: @escaping (String) -> Void) {
        self.model = model
        self.peeks = peeks
        self.send = send
        self.seek = seek
        self.openSource = openSource
    }

    public var body: some View {
        if let np = model.current {
            HStack(alignment: .top, spacing: 16) {
                // Clipped by its frame: a 16:9 video cover fills the square instead of
                // spilling over Mely and the title.
                Artwork(data: np.artwork, bundleId: np.sourceBundleId)
                    .frame(width: Self.artwork, height: Self.artwork)
                    .clipShape(RoundedRectangle(cornerRadius: MelyRadius.medium))
                    .contentShape(Rectangle())
                    .onTapGesture { openSource(np.sourceBundleId) }
                    .layoutProbe("music.artwork", row: "music", inside: "content")
                VStack(alignment: .leading, spacing: 6) {
                    Text(np.title).font(.system(size: MelyType.headline, weight: .semibold)).lineLimit(2)
                        .layoutProbe("music.title", inside: "music.info")
                    if let artist = np.artist {
                        Text(artist).font(.system(size: MelyType.body)).foregroundStyle(.white.opacity(MelyInk.strong)).lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Button { openSource(np.sourceBundleId) } label: {
                            HStack(spacing: 5) {
                                AppIcon(bundleId: np.sourceBundleId).frame(width: 14, height: 14)
                                Text(Self.appName(np.sourceBundleId)).font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.secondary))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .layoutProbe("music.source", row: "music.source", inside: "music.info")
                        if let peeks { PeekBell(peeks: peeks, app: np.sourceBundleId).layoutProbe("music.bell", row: "music.source", inside: "music.info") }
                    }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Progress(position: np.position(at: context.date), duration: np.duration,
                                 seek: np.canSeek ? seek : nil)
                            .layoutProbe("music.progress", inside: "music.info")
                    }
                    HStack(spacing: 22) {
                        control("backward.fill", "Предыдущий", enabled: !np.prohibitsSkip) { send(.previous) }
                        control(np.isPlaying ? "pause.fill" : "play.fill", np.isPlaying ? "Пауза" : "Воспроизвести",
                                size: 22, enabled: true) { send(.togglePlayPause) }
                        control("forward.fill", "Следующий", enabled: !np.prohibitsSkip) { send(.next) }
                    }
                    .layoutProbe("music.controls", inside: "music.info")
                    .frame(maxWidth: .infinity)
                }
                // As tall as the cover: the controls sit by it, not at the island's bottom.
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Self.artwork)
                .layoutProbe("music.info", row: "music", inside: "content")
            }
            .islandPart()
            .foregroundStyle(.white)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            Text("Сейчас ничего не играет").font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.secondary))
                .layoutProbe("music.empty", inside: "content")
                .islandPart()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func control(_ symbol: String, _ label: String, size: CGFloat = 15, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size)).frame(width: 34, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
        .help(label)
    }

    static let artwork: CGFloat = 150

    public static func appName(_ bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Previews of this app's new tracks: on (a bell) or off (crossed out).
private struct PeekBell: View {
    let peeks: NowPlayingPeeks
    let app: String
    @State private var hovered = false

    var body: some View {
        let muted = peeks.isMuted(app) || !peeks.isOn
        let name = MiniPlayerView.appName(app)
        Button { peeks.setMuted(app, !peeks.isMuted(app)) } label: {
            Image(systemName: muted ? "bell.slash" : "bell")
                .font(.system(size: MelyType.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(hovered ? MelyInk.primary : MelyInk.tertiary))
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!peeks.isOn)
        .onHover { hovered = $0 }
        .help(!peeks.isOn ? "Подсказка «Сейчас играет» выключена в настройках"
              : muted ? "Показывать подсказку «Сейчас играет» из \(name)" : "Не показывать подсказку «Сейчас играет» из \(name)")
        .accessibilityLabel(muted ? "Подсказки из \(name) выключены" : "Подсказки из \(name) включены")
    }
}

private struct Progress: View {
    let position: TimeInterval?
    let duration: TimeInterval?
    /// Jumps there; nil: the bar only shows the position.
    let seek: ((TimeInterval) -> Void)?
    /// Where the bar is being dragged to (0…1), while it is.
    @State private var dragging: CGFloat?
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 3) {
            // A live stream has no length: no bar to fill, the same height kept.
            GeometryReader { geo in
                let thick: CGFloat = seek != nil && (hovered || dragging != nil) ? 6 : 4
                Capsule().fill(.white.opacity(MelyFill.selected))
                    .overlay(alignment: .leading) {
                        Capsule().fill(.white.opacity(MelyInk.primary))
                            .frame(width: geo.size.width * (dragging ?? fraction))
                    }
                    .frame(height: thick)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(seekGesture(width: geo.size.width), including: seek != nil ? .all : .none)
                    .onHover { hovered = $0 }
                    .animation(.easeOut(duration: 0.12), value: thick)
            }
            // Easier to hit than to see: 14 pt to grab, 4 pt drawn, laid out as 4.
            .frame(height: 14)
            .padding(.vertical, -5)
            .opacity(hasLength ? 1 : 0)
            HStack {
                Text(Self.clock(dragging.flatMap { d in duration.map { Double(d) * $0 } } ?? position))
                    .font(.system(size: MelyType.micro)).monospacedDigit()
                Spacer()
                Text(Self.clock(duration)).font(.system(size: MelyType.micro)).monospacedDigit()
            }
            .foregroundStyle(.white.opacity(MelyInk.tertiary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Позиция \(Self.clock(position)) из \(Self.clock(duration))")
        .accessibilityAdjustableAction { direction in
            guard let seek, let position, let duration else { return }
            let step: TimeInterval = direction == .increment ? 10 : -10
            seek(min(duration, max(0, position + step)))
        }
    }

    /// A click jumps there, a drag shows where it will land and jumps on release.
    private func seekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragging = min(1, max(0, value.location.x / max(1, width)))
            }
            .onEnded { value in
                let target = min(1, max(0, value.location.x / max(1, width)))
                if let duration { seek?(Double(target) * duration) }
                dragging = nil
            }
    }

    private var hasLength: Bool { (duration ?? 0) > 0 }

    private var fraction: CGFloat {
        guard let position, let duration, duration > 0 else { return 0 }
        return CGFloat(min(1, max(0, position / duration)))
    }

    static func clock(_ t: TimeInterval?) -> String {
        guard let t, t.isFinite, t >= 0 else { return "–:––" }
        let s = Int(t)
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The cover, or the source app's icon when the player sends none.
struct Artwork: View {
    let data: Data?
    let bundleId: String

    var body: some View {
        if let data, let image = NSImage(data: data) {
            // Fills whatever frame it gets; the owner clips it to that frame.
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            AppIcon(bundleId: bundleId).padding(18)
                .background(.white.opacity(MelyFill.raised), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        }
    }
}

/// Left of the compact island: Mely always, and the cover next to it while music plays.
/// A focus takes the cover's place: Mely in its ring, the time beside her.
public struct CompactLeading: View {
    let music: NowPlayingModel?
    let pose: CharacterPose
    let focus: FocusModel?
    @Environment(\.islandCharacterSize) private var size
    @Environment(\.characterDrag) private var drag

    public init(music: NowPlayingModel?, pose: CharacterPose = .idle, focus: FocusModel? = nil) {
        self.music = music
        self.pose = pose
        self.focus = focus
    }

    public var body: some View {
        if let focus, focus.timer.isLive {
            CompactFocus(model: focus) { mely }
        } else {
            withMusic
        }
    }

    /// Out on the desktop, Mely is not in the notch too.
    private var mely: some View {
        MelyCharacter(pose: pose).frame(width: size, height: size)
            .opacity(drag?.isAway == true ? 0 : 1)
    }

    private var withMusic: some View {
        HStack(spacing: 6) {
            mely
            if let np = music?.current, np.isPlaying, let data = np.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size * 0.8, height: size * 0.8)
                    .clipShape(RoundedRectangle(cornerRadius: MelyRadius.small))
                    .accessibilityLabel("Играет: \(np.title)")
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: music?.current?.isPlaying)
    }
}

/// Three bars dancing while music plays: the compact island's sign of it. Animated by
/// Core Animation in the render server, so the app does no work per frame.
public struct EqualizerBars: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 11, height: 11))
        view.wantsLayer = true
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel("Играет музыка")
        let green = CGColor(srgbRed: 0.3, green: 0.8, blue: 0.45, alpha: 1)
        for (i, duration) in [0.42, 0.31, 0.53].enumerated() {
            let bar = CALayer()
            bar.backgroundColor = green
            bar.cornerRadius = 1.25
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.frame = CGRect(x: CGFloat(i) * 4, y: 0, width: 2.5, height: 11)
            let grow = CABasicAnimation(keyPath: "bounds.size.height")
            grow.fromValue = 4
            grow.toValue = 11
            grow.duration = duration
            grow.autoreverses = true
            grow.repeatCount = .infinity
            grow.timeOffset = Double(i) * 0.17
            bar.add(grow, forKey: "dance")
            view.layer?.addSublayer(bar)
        }
        return view
    }

    public func updateNSView(_ view: NSView, context: Context) {}
}
