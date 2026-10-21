import Foundation

/// How a look is drawn (task 6.1).
public enum CharacterKind: String, Codable, Sendable {
    /// Drawn in code: Mely's own characters, every pose, eyes after the pointer, wardrobe.
    case canvas
    /// No character: a small status icon instead.
    case minimal
}

/// A setting a look offers: a colour, a switch, a choice or a number.
public struct CustomizationOption: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Colours to pick from, `#RRGGBB`.
        case color([String])
        case toggle
        /// Values with their titles.
        case choice([Choice])
        case number(ClosedRange<Double>)
    }

    public struct Choice: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public init(_ id: String, _ title: String) {
            self.id = id
            self.title = title
        }
    }

    /// Stable key.
    public let id: String
    public let title: String
    public let kind: Kind
    public let defaultValue: CustomizationValue

    public init(id: String, title: String, kind: Kind, defaultValue: CustomizationValue) {
        self.id = id
        self.title = title
        self.kind = kind
        self.defaultValue = defaultValue
    }
}

public enum CustomizationValue: Codable, Equatable, Sendable {
    case color(String)
    case bool(Bool)
    case choice(String)
    case number(Double)

    public var color: String? { if case .color(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var choice: String? { if case .choice(let v) = self { v } else { nil } }
    public var number: Double? { if case .number(let v) = self { v } else { nil } }
}

/// One look in the gallery: what it is and what it offers. The drawing itself lives in
/// MelyUI behind the look's `id`.
public struct CharacterLook: Identifiable, Equatable, Sendable {
    public let id: String
    /// What it is ("Персик", "Лисёнок"); the character is always called Mely.
    public let title: String
    public let kind: CharacterKind
    public let customizations: [CustomizationOption]
    /// Whether hats, glasses and the rest fit it.
    public let hasWardrobe: Bool

    public init(id: String, title: String, kind: CharacterKind,
                customizations: [CustomizationOption] = [], hasWardrobe: Bool = false) {
        self.id = id
        self.title = title
        self.kind = kind
        self.customizations = customizations
        self.hasWardrobe = hasWardrobe
    }

    /// The user's values over the defaults.
    public func values(_ stored: [String: CustomizationValue]) -> [String: CustomizationValue] {
        var values: [String: CustomizationValue] = [:]
        for option in customizations { values[option.id] = stored[option.id] ?? option.defaultValue }
        return values
    }
}

/// What the character view needs to draw: which look, with which settings and clothes.
public struct CharacterAppearance: Equatable, Sendable {
    public var lookId: String
    public var values: [String: CustomizationValue]
    public var outfit: [AccessorySlot: Accessory]

    public init(lookId: String = BuiltInLooks.mely.id, values: [String: CustomizationValue] = [:],
                outfit: [AccessorySlot: Accessory] = [:]) {
        self.lookId = lookId
        self.values = values
        self.outfit = outfit
    }
}
