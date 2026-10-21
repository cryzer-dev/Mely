import Foundation

/// The looks Mely ships with: its own characters drawn in code, and the plain icons.
public enum BuiltInLooks {
    /// Mely by default: the cream bun of the logo.
    public static let cream = "#FFF6EE"
    /// The Japanese white peach (hakuto): cream with a pink blush on top.
    public static let whitePeach = "#FFE8EA"
    /// The orange peach: golden below, rosy above.
    public static let peach = "#FFB98C"
    public static let yellowPeach = "#FFCF5C"
    /// Smooth and glossy, deep red over yellow.
    public static let nectarine = "#E8475A"
    /// The blood peach: dark red all over.
    public static let bloodPeach = "#B3364D"

    public static let mely = CharacterLook(
        id: "mely", title: "Персик", kind: .canvas,
        customizations: [
            bodyColor([cream, whitePeach, peach, yellowPeach, nectarine, bloodPeach]),
            CustomizationOption(id: "crease", title: "Бороздка", kind: .toggle, defaultValue: .bool(false)),
            CustomizationOption(id: "leaf", title: "Листик", kind: .toggle, defaultValue: .bool(true)),
            CustomizationOption(id: "cheeks", title: "Румянец", kind: .toggle, defaultValue: .bool(true)),
        ],
        hasWardrobe: true)

    public static let fawn = CharacterLook(
        id: "fawn", title: "Оленёнок", kind: .canvas,
        customizations: [
            bodyColor(["#C98A5B", "#B07048", "#D9A574", "#9C7A6A"]),
            CustomizationOption(id: "spots", title: "Пятнышки", kind: .toggle, defaultValue: .bool(true)),
            CustomizationOption(id: "antlers", title: "Рожки", kind: .toggle, defaultValue: .bool(true)),
            CustomizationOption(id: "cheeks", title: "Румянец", kind: .toggle, defaultValue: .bool(true)),
        ],
        hasWardrobe: true)

    public static let lamb = CharacterLook(
        id: "lamb", title: "Барашек", kind: .canvas,
        customizations: [
            bodyColor(["#FBF7F0", "#F1E4D3", "#E8E6EE", "#FFE3EC"], title: "Шерсть"),
            CustomizationOption(id: "face", title: "Мордочка",
                                kind: .color(["#E9C9AE", "#8C6D5C", "#4E4245"]), defaultValue: .color("#E9C9AE")),
            CustomizationOption(id: "horns", title: "Рожки", kind: .toggle, defaultValue: .bool(true)),
        ],
        hasWardrobe: true)

    public static let conure = CharacterLook(
        id: "conure", title: "Аратинга", kind: .canvas,
        customizations: [
            CustomizationOption(id: "plumage", title: "Оперение",
                                kind: .choice([.init("sun", "Солнечная"), .init("green", "Зелёная"), .init("blue", "Голубая")]),
                                defaultValue: .choice("sun")),
            CustomizationOption(id: "crest", title: "Хохолок", kind: .toggle, defaultValue: .bool(true)),
            CustomizationOption(id: "cheeks", title: "Румянец", kind: .toggle, defaultValue: .bool(true)),
        ],
        hasWardrobe: true)

    public static let fox = CharacterLook(
        id: "fox", title: "Лисёнок", kind: .canvas,
        customizations: [
            CustomizationOption(id: "fur", title: "Мех",
                                kind: .choice([.init("red", "Рыжий"), .init("arctic", "Полярный"), .init("silver", "Чернобурый")]),
                                defaultValue: .choice("red")),
            CustomizationOption(id: "tail", title: "Хвост", kind: .toggle, defaultValue: .bool(true)),
            CustomizationOption(id: "cheeks", title: "Румянец", kind: .toggle, defaultValue: .bool(true)),
        ],
        hasWardrobe: true)

    /// No character: a status icon in the notch.
    public static let minimal = CharacterLook(id: "minimal", title: "Без персонажа — значки", kind: .minimal)

    public static let all: [CharacterLook] = [mely, fawn, lamb, conure, fox, minimal]

    static func bodyColor(_ palette: [String], title: String = "Цвет") -> CustomizationOption {
        CustomizationOption(id: "color", title: title, kind: .color(palette), defaultValue: .color(palette[0]))
    }
}
