import Foundation
import MelyCore

/// The previews of the focus: their ids, texts and buttons. `FocusIntegration` shows them and
/// runs their buttons (`Action`); the snapshots lay them out.
public enum FocusPeeks {
    /// Every focus preview's id starts with this; the app routes their buttons by it.
    public static let prefix = "focus-"
    public static let finishedId = "focus-finished"
    public static let breakId = "focus-break"
    public static let breakOverId = "focus-break-over"
    public static let awayId = "focus-away"
    public static func meetingId(_ meeting: String) -> String { "focus-meeting-\(meeting)" }
    /// The summary of messages held during the session: not a focus preview, the tab's.
    public static let heldId = "messages-held"

    /// The buttons' ids.
    public enum Action: String {
        case takeBreak = "break", more, taskDone = "done", continueFocus = "continue", resume, stop, skip, endNow = "end"
    }

    /// «Пока ты работал: 3 сообщения» after the session; a click opens the list.
    public static func held(_ count: Int) -> PeekContent {
        PeekContent(id: heldId, symbol: "bell.badge.fill", tint: .blue, title: MessageHold.summary(count),
                    subtitle: "Они во вкладке «Уведомления»",
                    actions: [PeekAction(id: "show", title: "Показать", isPrimary: true)])
    }

    /// Lasting ones stay this long unless answered: the time is up, nothing goes on by itself.
    static let lasts: TimeInterval = 10 * 60

    /// «Фокус окончен», the time and the task under it: a break, ten minutes more, and with a
    /// task «Задача готова». It passes (no «×»: three buttons leave the title no room
    /// beside it); the card under Mely keeps the choice until answered.
    public static func finished(worked: TimeInterval, task: String?) -> PeekContent {
        var content = PeekContent(id: finishedId, symbol: "checkmark", tint: .focus, title: "Фокус окончен",
                                  subtitle: FocusStats.format(worked) + (task.map { " · \($0)" } ?? " · время отдохнуть"),
                                  actions: [PeekAction(id: Action.more.rawValue, title: "Ещё 10 мин", folds: true)]
                                      + (task == nil ? [] : [PeekAction(id: Action.taskDone.rawValue, title: "Задача готова")])
                                      + [PeekAction(id: Action.takeBreak.rawValue, title: "Перерыв", isPrimary: true)])
        content.tapRunsAction = false
        return content
    }

    /// The break began by itself (the setting): it can be skipped.
    public static func breakStarted(length: TimeInterval, worked: TimeInterval) -> PeekContent {
        var content = PeekContent(id: breakId, symbol: "cup.and.saucer.fill", tint: .rest,
                                  title: "Перерыв \(FocusStats.format(length))",
                                  subtitle: "Фокус окончен · \(FocusStats.format(worked))",
                                  actions: [PeekAction(id: Action.skip.rawValue, title: "Пропустить")])
        content.tapRunsAction = false
        return content
    }

    /// «Перерыв окончен»: the same length and task again, or enough.
    public static func breakOver(duration: TimeInterval, task: String?, now: Date = Date()) -> PeekContent {
        PeekContent(id: breakOverId, symbol: "cup.and.saucer.fill", tint: .rest, title: "Перерыв окончен",
                    subtitle: "Дальше \(FocusStats.format(duration))" + (task.map { " · \($0)" } ?? ""),
                    actions: [PeekAction(id: Action.stop.rawValue, title: "Хватит"),
                              PeekAction(id: Action.continueFocus.rawValue, title: "Продолжить", isPrimary: true)],
                    staysUntil: now.addingTimeInterval(lasts))
    }

    /// Back after an away, a lock or sleep: the pause waits for the user.
    public static func away(_ time: TimeInterval, now: Date = Date()) -> PeekContent {
        PeekContent(id: awayId, symbol: "pause.fill", tint: .focus, title: "Фокус на паузе",
                    subtitle: "Тебя не было \(FocusStats.format(time))",
                    actions: [PeekAction(id: Action.stop.rawValue, title: "Стоп"),
                              PeekAction(id: Action.resume.rawValue, title: "Продолжить", isPrimary: true)],
                    staysUntil: now.addingTimeInterval(lasts))
    }

    /// A meeting starts before the end: the title counts down to it, until it starts. The
    /// calendar's own reminder (with «Подключиться») may be up too: this one passes over it.
    public static func meeting(_ meeting: FocusMeeting) -> PeekContent {
        var content = PeekContent(id: meetingId(meeting.id), symbol: "calendar.badge.clock", tint: .focus, title: meeting.title,
                                  subtitle: "Встреча начнётся до конца фокуса",
                                  actions: [PeekAction(id: Action.endNow.rawValue, title: "Закончить сейчас", isPrimary: true)],
                                  until: meeting.start, yieldsToLasting: true)
        content.tapRunsAction = false
        return content
    }
}
