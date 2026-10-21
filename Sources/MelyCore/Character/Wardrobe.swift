import Foundation

/// Where on the character a thing is worn; one thing per slot (task 6.10).
public enum AccessorySlot: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case head, eyes, neck, held, back

    public var title: String {
        switch self {
        case .head: "Голова"
        case .eyes: "Глаза"
        case .neck: "Шея"
        case .held: "В лапах"
        case .back: "За спиной"
        }
    }
}

/// Things to wear. Drawn once in Mely's own coordinates and placed on each character
/// by its anchor points, so one hat fits every character in every pose.
public enum Accessory: String, Codable, CaseIterable, Sendable, Identifiable {
    case wizardHat, witchHat, santaHat, beanie, partyHat, crown, headphones
    case roundGlasses, sunglasses
    case stripedScarf, garland, bowTie
    case wand, pumpkin, gift
    case cape

    public var id: String { rawValue }

    public var slot: AccessorySlot {
        switch self {
        case .wizardHat, .witchHat, .santaHat, .beanie, .partyHat, .crown, .headphones: .head
        case .roundGlasses, .sunglasses: .eyes
        case .stripedScarf, .garland, .bowTie: .neck
        case .wand, .pumpkin, .gift: .held
        case .cape: .back
        }
    }

    public var title: String {
        switch self {
        case .wizardHat: "Шляпа волшебника"
        case .witchHat: "Шляпа ведьмы"
        case .santaHat: "Шапка Деда Мороза"
        case .beanie: "Вязаная шапочка"
        case .partyHat: "Праздничный колпак"
        case .crown: "Корона"
        case .headphones: "Наушники"
        case .roundGlasses: "Круглые очки"
        case .sunglasses: "Солнечные очки"
        case .stripedScarf: "Полосатый шарф"
        case .garland: "Шарф-гирлянда"
        case .bowTie: "Бабочка"
        case .wand: "Палочка"
        case .pumpkin: "Тыква"
        case .gift: "Подарок"
        case .cape: "Плащ"
        }
    }

    public static func items(in slot: AccessorySlot) -> [Accessory] { allCases.filter { $0.slot == slot } }
}

/// A month and day, for seasons that repeat every year.
public struct MonthDay: Comparable, Sendable {
    public let month: Int
    public let day: Int
    public init(_ month: Int, _ day: Int) {
        self.month = month
        self.day = day
    }
    public static func < (a: MonthDay, b: MonthDay) -> Bool { (a.month, a.day) < (b.month, b.day) }
}

/// Ready sets put on in one click (task 6.11).
public enum OutfitSet: String, CaseIterable, Sendable, Identifiable {
    case wizard, halloween, newYear

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wizard: "Волшебник"
        case .halloween: "Хэллоуин"
        case .newYear: "Новый год"
        }
    }

    public var items: [Accessory] {
        switch self {
        case .wizard: [.wizardHat, .roundGlasses, .stripedScarf, .wand]
        case .halloween: [.witchHat, .cape, .pumpkin]
        case .newYear: [.santaHat, .garland, .gift]
        }
    }

    /// When it is put on by itself; may wrap over the new year.
    public var season: (from: MonthDay, to: MonthDay)? {
        switch self {
        case .wizard: nil
        case .halloween: (MonthDay(10, 25), MonthDay(11, 1))
        case .newYear: (MonthDay(12, 20), MonthDay(1, 10))
        }
    }

    public var outfit: [AccessorySlot: Accessory] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.slot, $0) })
    }
}

/// What one character wears, and when the user last chose it.
public struct Outfit: Codable, Equatable, Sendable {
    public var items: [AccessorySlot: Accessory]
    /// The user's own choice; a choice made during a season beats that season.
    public var chosenAt: Date?

    public init(items: [AccessorySlot: Accessory] = [:], chosenAt: Date? = nil) {
        self.items = items
        self.chosenAt = chosenAt
    }
}

public enum Wardrobe {
    /// The season running on `date`, in the user's local calendar.
    public static func season(on date: Date, calendar: Calendar = .current) -> OutfitSet? {
        let today = MonthDay(calendar.component(.month, from: date), calendar.component(.day, from: date))
        return OutfitSet.allCases.first { set in
            guard let s = set.season else { return false }
            return s.from <= s.to ? (s.from <= today && today <= s.to) : (today >= s.from || today <= s.to)
        }
    }

    /// When the season running on `date` began.
    static func seasonStart(_ set: OutfitSet, containing date: Date, calendar: Calendar) -> Date? {
        guard let s = set.season else { return nil }
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        // A season over the new year that is in its January part started the year before.
        let startYear = s.from > s.to && month < s.from.month ? year - 1 : year
        return calendar.date(from: DateComponents(year: startYear, month: s.from.month, day: s.from.day))
    }

    /// What the character wears now: the season's set while it runs, unless the user
    /// dressed it during this season; the user's own outfit otherwise.
    public static func worn(_ outfit: Outfit, seasonal: Bool, now: Date = Date(),
                            calendar: Calendar = .current) -> [AccessorySlot: Accessory] {
        guard seasonal, let set = season(on: now, calendar: calendar),
              let start = seasonStart(set, containing: now, calendar: calendar) else { return outfit.items }
        if let chosen = outfit.chosenAt, chosen >= start { return outfit.items }
        return set.outfit
    }
}
