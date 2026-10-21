import SwiftUI
import MelyCore

/// What the island window shows right now. The window controller owns it and drives
/// `mode` from `IslandStateMachine`; content comes from `IslandModel` (task 1.3).
@MainActor
@Observable
public final class IslandPresentation {
    public enum Mode: Equatable, Sendable { case hidden, compact, peek, expanded, greeting }

    public var mode: Mode = .hidden
    /// When the launch greeting started (mode `.greeting`).
    public var greetingStart = Date()
    /// What a peek shows: a short card under the notch that folds back by itself.
    public var peek: PeekContent?
    public var geometry: IslandScreenGeometry
    /// Files dropped on the island; nil while nothing takes them.
    @ObservationIgnored public var dropFiles: (([URL]) -> Void)?
    /// A file is being dragged over the island.
    public var isDropTargeted = false
    /// The «×» of a lasting preview (a meeting reminder).
    @ObservationIgnored public var dismissPeek: (() -> Void)?

    public static let expandedSize = CGSize(width: 720, height: 300)
    /// Width added on each side of the notch in compact mode (character left, status right).
    public static let compactSideWidth: CGFloat = 84
    /// Concave ears that blend the island into the menu bar.
    public static let earRadius: CGFloat = 8

    public init(geometry: IslandScreenGeometry) {
        self.geometry = geometry
    }

    /// Size of the black shape, ears included.
    public var islandSize: CGSize {
        switch mode {
        case .hidden:
            return CGSize(width: geometry.width + 2 * Self.earRadius, height: geometry.height)
        case .compact:
            return CGSize(width: geometry.width + 2 * Self.compactSideWidth + 2 * Self.earRadius,
                          height: geometry.height)
        case .peek:
            return CGSize(width: Self.peekWidth, height: geometry.height + Self.peekBodyHeight)
        case .expanded:
            return Self.expandedSize
        case .greeting:
            return CGSize(width: Self.greetingWidth, height: geometry.height + 104)
        }
    }

    public static let peekWidth: CGFloat = 460
    public static let greetingWidth: CGFloat = 420
    public static let peekBodyHeight: CGFloat = 62

    /// The panel is fixed at this size; only the shape inside animates.
    public static let panelSize = CGSize(width: expandedSize.width + 40, height: expandedSize.height + 40)
}

/// A peek card: an icon, a title and one line.
public struct PeekContent: Equatable, Sendable {
    public var id: String
    public var symbol: String
    public var tint: Tint
    public var title: String
    public var subtitle: String
    /// Bundle id whose app icon replaces the symbol, when installed.
    public var appBundleId: String?
    /// A click opens that app instead of expanding the island (a mirrored message).
    public var opensApp = false
    /// A button on the right ("Подключиться"); a click runs the action registered for `id`.
    public var actionTitle: String?
    /// A cover replaces the icon (a new track).
    public var artwork: Data?
    /// A meeting reminder: stays until then, with a live countdown after the title and a
    /// close button; other previews pass over it and it comes back.
    public var until: Date?

    public enum Tint: Sendable { case blue, green, orange, red, yellow, gray }

    public init(id: String, symbol: String, tint: Tint, title: String, subtitle: String, appBundleId: String? = nil,
                opensApp: Bool = false, actionTitle: String? = nil, artwork: Data? = nil, until: Date? = nil) {
        self.until = until
        self.opensApp = opensApp
        self.actionTitle = actionTitle
        self.artwork = artwork
        self.id = id
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.appBundleId = appBundleId
    }
}
