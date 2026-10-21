import Foundation

/// Mely's little extras (task 7.5): a wink now and then, a burst of confetti on special
/// days. Rare (minutes apart) and only while nothing needs the user, so they never get in
/// the way of work.
public enum CharacterQuirks {
    public enum Quirk: Equatable, Sendable {
        case wink
        /// Confetti, on an occasion.
        case party(Occasion)
    }

    public enum Occasion: Equatable, Sendable {
        /// Friday from 17:00.
        case fridayEvening
        /// 31 December and 1 January.
        case newYear
        case birthday

        public var title: String {
            switch self {
            case .fridayEvening: "Пятница!"
            case .newYear: "С Новым годом!"
            case .birthday: "С днём рождения!"
            }
        }
    }

    /// UserDefaults key of the user's birthday, "MM-dd" (Settings → Основные).
    public static let birthdayKey = "birthday"

    /// Between two quirks: three to seven minutes.
    public static let interval: ClosedRange<TimeInterval> = 180...420

    /// Only in calm poses: never over an approval, a question, an error or sleep.
    public static func allowed(in pose: CharacterPose) -> Bool {
        pose == .idle || pose == .dancing || pose == .happy
    }

    public static func occasion(on date: Date, birthday: MonthDay?, calendar: Calendar = .current) -> Occasion? {
        let c = calendar.dateComponents([.month, .day, .weekday, .hour], from: date)
        guard let month = c.month, let day = c.day else { return nil }
        if let birthday, birthday.month == month, birthday.day == day { return .birthday }
        if (month == 12 && day == 31) || (month == 1 && day == 1) { return .newYear }
        if c.weekday == 6, (c.hour ?? 0) >= 17 { return .fridayEvening }
        return nil
    }

    /// What to do when a quirk is due: on a special day every other one is confetti.
    public static func pick(on date: Date, birthday: MonthDay?, roll: Double, calendar: Calendar = .current) -> Quirk {
        if let occasion = occasion(on: date, birthday: birthday, calendar: calendar), roll < 0.5 { return .party(occasion) }
        return .wink
    }

    public static func birthday(from stored: String?) -> MonthDay? {
        guard let parts = stored?.split(separator: "-"), parts.count == 2,
              let m = Int(parts[0]), let d = Int(parts[1]), (1...12).contains(m), (1...31).contains(d) else { return nil }
        return MonthDay(m, d)
    }
}
