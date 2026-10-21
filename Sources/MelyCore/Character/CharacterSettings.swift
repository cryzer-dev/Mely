import Foundation
import Observation

/// The user's character: which look, its settings and clothes per look, hidden looks
/// (tasks 6.5, 6.10). Kept in UserDefaults as one JSON value.
@MainActor
@Observable
public final class CharacterSettings {
    struct Stored: Codable, Equatable {
        var selected: String = BuiltInLooks.mely.id
        var hidden: Set<String> = []
        var values: [String: [String: CustomizationValue]] = [:]
        var outfits: [String: Outfit] = [:]
        var seasonal = true
    }

    public static let defaultsKey = "character"

    private let defaults: UserDefaults
    private var stored: Stored { didSet { save() } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stored = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    // MARK: Looks

    public var allLooks: [CharacterLook] { BuiltInLooks.all }

    /// What the gallery offers: everything not hidden (the chosen one always).
    public func visibleLooks(showHidden: Bool = false) -> [CharacterLook] {
        allLooks.filter { showHidden || !stored.hidden.contains($0.id) || $0.id == stored.selected }
    }

    /// The chosen look; Mely's own when the chosen one is gone (a look from an older version).
    public var look: CharacterLook {
        allLooks.first { $0.id == stored.selected } ?? BuiltInLooks.mely
    }

    public func select(_ id: String) {
        guard allLooks.contains(where: { $0.id == id }), id != stored.selected || stored.hidden.contains(id) else { return }
        stored.selected = id
        stored.hidden.remove(id)
    }

    public func isHidden(_ id: String) -> Bool { stored.hidden.contains(id) }

    public func setHidden(_ id: String, _ hidden: Bool) {
        if hidden { stored.hidden.insert(id) } else { stored.hidden.remove(id) }
    }

    // MARK: Customization

    public func values(for look: CharacterLook) -> [String: CustomizationValue] {
        look.values(stored.values[look.id] ?? [:])
    }

    /// A control echoing the current value back is not a change: nothing is written.
    public func set(_ option: String, to value: CustomizationValue, for lookId: String) {
        guard let look = allLooks.first(where: { $0.id == lookId }), values(for: look)[option] != value else { return }
        stored.values[lookId, default: [:]][option] = value
    }

    public func reset(_ lookId: String) {
        stored.values[lookId] = nil
    }

    // MARK: Wardrobe

    public var dressesBySeason: Bool {
        get { stored.seasonal }
        set { if newValue != stored.seasonal { stored.seasonal = newValue } }
    }

    public func outfit(for lookId: String) -> Outfit { stored.outfits[lookId] ?? Outfit() }

    /// Puts on (or takes off, with nil) one thing; the user chose it now.
    public func wear(_ accessory: Accessory?, in slot: AccessorySlot, for lookId: String, now: Date = Date()) {
        var outfit = worn(for: lookId, now: now)
        // The same thing again is not a choice: it must not override a season.
        guard outfit[slot] != accessory else { return }
        outfit[slot] = accessory
        stored.outfits[lookId] = Outfit(items: outfit, chosenAt: now)
    }

    public func wear(_ set: OutfitSet?, for lookId: String, now: Date = Date()) {
        stored.outfits[lookId] = Outfit(items: set?.outfit ?? [:], chosenAt: now)
    }

    /// What the look wears now, seasons included.
    public func worn(for lookId: String, now: Date = Date()) -> [AccessorySlot: Accessory] {
        Wardrobe.worn(outfit(for: lookId), seasonal: stored.seasonal, now: now)
    }

    /// Everything the character view needs.
    public func appearance(now: Date = Date()) -> CharacterAppearance {
        let look = look
        return CharacterAppearance(lookId: look.id, values: values(for: look),
                                   outfit: look.hasWardrobe ? worn(for: look.id, now: now) : [:])
    }
}
