import Foundation
import Observation

/// "Что нового" for a release: a few tiles shown once in the island after the update.
public struct WhatsNew: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let symbol: String
        public let title: String
        public let text: String
    }

    /// The tiles' colour: the feature's own.
    public enum Accent: Sendable { case working, focus }

    /// "1.6": shown for 1.6.0, 1.6.1…, not for 1.60.
    public let version: String
    public let items: [Item]
    /// The main button: «Попробовать задачи», «Попробовать фокус».
    public let tryTitle: String
    public let accent: Accent

    public static let current = WhatsNew(version: "1.7", items: [
        Item(symbol: "timer", title: "Фокус", text: "Таймер рядом с Mely: ⌃⌥P или ▶︎ у задачи"),
        Item(symbol: "bell.slash.fill", title: "Тишина", text: "Сообщения ждут до перерыва"),
        Item(symbol: "hourglass", title: "Сколько ушло", text: "Честное время на задачу и за день"),
    ], tryTitle: "Попробовать фокус", accent: .focus)

    public func matches(_ appVersion: String) -> Bool {
        appVersion == version || appVersion.hasPrefix(version + ".")
    }
}

/// Whether the card is up, and whether it was already seen for its release.
@MainActor
@Observable
public final class WhatsNewState {
    public let card: WhatsNew
    public private(set) var isShowing = false

    @ObservationIgnored private let defaults: UserDefaults
    static let seenKey = "whatsNewSeen"
    /// `defaults write dev.mely.app.dev whatsNewPreview -bool YES`: shown in any version
    /// until closed, to try it in a dev build.
    static let previewKey = "whatsNewPreview"

    public init(card: WhatsNew = .current, defaults: UserDefaults = .standard) {
        self.card = card
        self.defaults = defaults
    }

    /// On opening the island: the first time in this release, the card shows by itself.
    public func showIfNew(appVersion: String) {
        guard defaults.string(forKey: Self.seenKey) != card.version else { return }
        guard card.matches(appVersion) || defaults.bool(forKey: Self.previewKey) else { return }
        isShowing = true
    }

    /// «Что нового» on the update preview: again, even if seen.
    public func show() {
        isShowing = true
    }

    /// «Понятно», «×», Esc, «Попробовать задачи»: closed for good in this release.
    public func dismiss() {
        isShowing = false
        defaults.set(card.version, forKey: Self.seenKey)
    }
}
