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
    /// The preview's second button.
    @ObservationIgnored public var peekSecondaryAction: (() -> Void)?
    /// The main button of a preview with two (a click elsewhere on it only opens the island).
    @ObservationIgnored public var peekPrimaryAction: (() -> Void)?

    /// The open island at its largest (four sessions and the limits); shorter pages make it
    /// shorter (`contentHeight`).
    public static let expandedSize = CGSize(width: 640, height: 340)
    /// The chat and the request cards: the page of the island as it was, 300 pt in all.
    public static let fullPage: CGFloat = 240
    /// What the open page needs below the header (`IslandContentHeightKey`); nil: all of it.
    public var contentHeight: CGFloat?
    /// Never shorter than the big Mely on the left.
    public static let minContentHeight: CGFloat = 120
    /// How low the left column reaches («Обновить» under Mely); 0: just Mely.
    public var columnHeight: CGFloat = 0
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
            return CGSize(width: Self.expandedSize.width, height: expandedHeight)
        case .greeting:
            return CGSize(width: Self.greetingWidth, height: geometry.height + 104)
        }
    }

    /// Header level with the notch, the page, and the paddings around it.
    var expandedHeight: CGFloat {
        guard let contentHeight else { return Self.expandedSize.height }
        let header = max(28, geometry.height)
        return min(Self.expandedSize.height, header + 8 + max(Self.minContentHeight, columnHeight, contentHeight) + 20)
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
    /// A second, quieter button before it ("+1 ч"); a click runs the owner's second action.
    /// With it, the main action is its own button, not a click anywhere on the preview.
    public var secondaryActionTitle: String?
    /// A lasting preview that gives way to a lasting one already up (a meeting): it passes
    /// over it like a short preview and the meeting comes back.
    public var yieldsToLasting = false
    /// A cover replaces the icon (a new track).
    public var artwork: Data?
    /// An event reminder: the event's start, counted down after the title ("через 4 мин",
    /// then "идёт 12 мин"). The preview stays, with a close button; other previews pass over
    /// it and it comes back.
    public var until: Date?
    /// When the reminder goes by itself (the event's end); nil: at `until`.
    public var staysUntil: Date?

    /// When a lasting preview runs out; nil for a passing one.
    public var lastsUntil: Date? { staysUntil ?? until }

    public enum Tint: Sendable { case blue, green, orange, red, yellow, gray }

    public init(id: String, symbol: String, tint: Tint, title: String, subtitle: String, appBundleId: String? = nil,
                opensApp: Bool = false, actionTitle: String? = nil, secondaryActionTitle: String? = nil, artwork: Data? = nil,
                until: Date? = nil, staysUntil: Date? = nil, yieldsToLasting: Bool = false) {
        self.until = until
        self.secondaryActionTitle = secondaryActionTitle
        self.yieldsToLasting = yieldsToLasting
        self.staysUntil = staysUntil
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
