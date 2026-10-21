import Foundation
import Observation

/// The chat's route and model, shared by the chat's model pill and the settings window.
@MainActor
@Observable
public final class ChatPreferences {
    public var route: ChatRoute {
        didSet {
            guard route != oldValue else { return }
            defaults.set(route.rawValue, forKey: Self.routeKey)
            onRouteChange?()
        }
    }
    public var model: ChatModel {
        didSet { defaults.set(model.rawValue, forKey: Self.modelKey) }
    }
    /// Filled by the integration: what each route needs is there.
    public var claudeFound = false
    public var hasKey = false
    /// The conversations of the two routes do not mix: switching starts a new one.
    @ObservationIgnored public var onRouteChange: (() -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    static let routeKey = "chatRoute"
    static let modelKey = "chatModel"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        route = ChatRoute(rawValue: defaults.string(forKey: Self.routeKey) ?? "") ?? .default
        model = ChatModel(rawValue: defaults.string(forKey: Self.modelKey) ?? "") ?? .default
    }

    /// What is missing for a route, or nil when it can answer.
    public func setupHint(for route: ChatRoute) -> String? {
        switch route {
        case .subscription:
            claudeFound ? nil : "Claude Code не найден. Установите его или переключите чат на ключ API"
        case .apiKey:
            hasKey ? nil : "Чтобы спрашивать Claude, добавьте ключ API"
        }
    }

    public var setupHint: String? { setupHint(for: route) }
}
