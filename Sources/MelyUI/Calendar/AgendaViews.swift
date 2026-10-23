import SwiftUI
import MelyCore

/// The "Сегодня" tab: all-day events on top, then the day in order; past ones dimmed,
/// the current one marked, a call link gets «Подключиться».
public struct AgendaView: View {
    let agenda: Agenda?
    let isOn: Bool
    let enable: () -> Void
    let join: (CalendarEvent) -> Void
    /// A fixed clock (the README picture); nil: the real one.
    let now: Date?

    public init(agenda: Agenda?, isOn: Bool = true, now: Date? = nil, enable: @escaping () -> Void = {},
                join: @escaping (CalendarEvent) -> Void) {
        self.agenda = agenda
        self.isOn = isOn
        self.now = now
        self.enable = enable
        self.join = join
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if !isOn {
                VStack(spacing: 8) {
                    Image(systemName: "calendar").font(.system(size: 20)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                    Text("Календарь не подключён").font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.strong))
                    Text("События на сегодня, новые встречи и напоминания с «Подключиться»")
                        .font(.system(size: MelyType.caption)).foregroundStyle(.white.opacity(MelyInk.tertiary))
                    Button("Подключить календарь", action: enable)
                        .buttonStyle(.plain)
                        .font(.system(size: MelyType.body, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(.white, in: Capsule())
                }
                .layoutProbe("agenda.off", inside: "content")
                .islandPart()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let agenda {
                if agenda.isEmpty {
                    empty(agenda.nextTomorrow)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(agenda.allDay) { event in
                                HStack(spacing: 8) {
                                    Text("весь день").font(.system(size: MelyType.caption, weight: .medium)).foregroundStyle(.white.opacity(MelyInk.secondary))
                                        .frame(width: 70, alignment: .leading)
                                    Text(event.title).font(.system(size: MelyType.body, weight: .medium)).lineLimit(1)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.white.opacity(MelyFill.card), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
                                .layoutProbe("agenda.allday.\(event.id)", inside: "agenda.list")
                            }
                            ForEach(agenda.timed) { event in
                                EventRow(event: event, now: now ?? context.date, join: { join(event) })
                                    .layoutProbe("agenda.event.\(event.id)", inside: "agenda.list")
                            }
                        }
                        .islandPart()
                    }
                    .layoutProbe("agenda.list", inside: "content", scrolls: true)
                }
            } else {
                Text("Нет доступа к календарям").font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.secondary))
                    .layoutProbe("agenda.denied", inside: "content")
                    .islandPart()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(.white)
    }

    private func empty(_ next: CalendarEvent?) -> some View {
        VStack(spacing: 6) {
            Text("Событий на сегодня нет").font(.system(size: MelyType.title)).foregroundStyle(.white.opacity(MelyInk.strong))
            if let next {
                Text("Завтра в \(next.start.formatted(date: .omitted, time: .shortened)) — \(next.title)")
                    .font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.tertiary)).lineLimit(1)
            }
        }
        .layoutProbe("agenda.empty", inside: "content")
        .islandPart()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let now: Date
    let join: () -> Void

    var body: some View {
        let isNow = event.isNow(now)
        let isPast = event.end <= now
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(event.start.formatted(date: .omitted, time: .shortened)).font(.system(size: MelyType.body, weight: .semibold)).monospacedDigit()
                Text(event.end.formatted(date: .omitted, time: .shortened)).font(.system(size: MelyType.caption)).monospacedDigit()
                    .foregroundStyle(.white.opacity(MelyInk.tertiary))
            }
            .frame(width: 44, alignment: .leading)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isNow ? Color(red: 0.3, green: 0.8, blue: 0.45) : .white.opacity(MelyInk.faint))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: MelyType.body, weight: .semibold)).lineLimit(1)
                if let detail = event.meeting?.service.title ?? event.location, !detail.isEmpty {
                    Text(detail).font(.system(size: MelyType.footnote)).foregroundStyle(.white.opacity(MelyInk.secondary)).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if isNow {
                Text("сейчас").font(.system(size: MelyType.caption, weight: .semibold))
                    .foregroundStyle(Color(red: 0.3, green: 0.8, blue: 0.45))
            } else if !isPast, event.start.timeIntervalSince(now) < 3600 {
                Text("через \(max(1, Int(event.start.timeIntervalSince(now) / 60))) мин").font(.system(size: MelyType.caption))
                    .foregroundStyle(.white.opacity(MelyInk.secondary))
            }
            if event.meeting != nil, !isPast {
                Button("Подключиться", action: join)
                    .buttonStyle(.plain)
                    .font(.system(size: MelyType.footnote, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(isNow ? 0.95 : 0.75), in: Capsule())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(isNow ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: MelyRadius.medium))
        .opacity(isPast ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Calendars to show, reminder time, where meetings open; how to add Yandex.
public struct CalendarSettingsView: View {
    public struct CalendarItem: Identifiable, Sendable {
        public let id: String
        public let title: String
        public let source: String
        public init(id: String, title: String, source: String) {
            self.id = id
            self.title = title
            self.source = source
        }
    }

    @Bindable var settings: CalendarSettings
    let calendars: [CalendarItem]
    let hasYandex: Bool
    let openAccounts: () -> Void
    let close: () -> Void

    public init(settings: CalendarSettings, calendars: [CalendarItem], hasYandex: Bool,
                openAccounts: @escaping () -> Void, close: @escaping () -> Void) {
        self.settings = settings
        self.calendars = calendars
        self.hasYandex = hasYandex
        self.openAccounts = openAccounts
        self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Календарь").font(.title3.weight(.semibold))
            if !hasYandex {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Как подключить Яндекс Календарь").font(.headline)
                        Text("1. В Яндекс ID создайте пароль приложения для календаря (CalDAV).")
                        Text("2. Системные настройки → Учётные записи интернета → Добавить → Другая → Учётная запись CalDAV.")
                        Text("3. Тип «Вручную», логин — ваша почта Яндекса, пароль — пароль приложения, сервер — caldav.yandex.ru.")
                        HStack {
                            Link("Пароли приложений", destination: URL(string: "https://id.yandex.ru/security/app-passwords")!)
                            Button("Открыть учётные записи", action: openAccounts).buttonStyle(.link)
                        }
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Показывать календари").font(.headline)
            List {
                ForEach(Dictionary(grouping: calendars, by: \.source).sorted { $0.key < $1.key }, id: \.key) { source, items in
                    Section(source) {
                        ForEach(items) { item in
                            Toggle(item.title, isOn: Binding(
                                get: { !settings.hiddenCalendars.contains(item.id) },
                                set: { on in if on { settings.hiddenCalendars.remove(item.id) } else { settings.hiddenCalendars.insert(item.id) } }))
                        }
                    }
                }
            }
            .frame(height: 180)
            Picker("Напоминать о встрече", selection: $settings.reminderMinutes) {
                ForEach(CalendarSettings.reminderChoices, id: \.self) { m in
                    Text(m == 0 ? "не напоминать" : "за \(m) мин").tag(m)
                }
            }
            Text("«Подключиться» открывает встречу").font(.headline)
            ForEach([MeetingLink.Service.telemost, .zoom, .teams], id: \.self) { service in
                Picker(service.title, selection: Binding(
                    get: { settings.opensInApp(service) },
                    set: { inApp in if inApp { settings.browserServices.remove(service) } else { settings.browserServices.insert(service) } })) {
                    Text("в приложении").tag(true)
                    Text("в браузере").tag(false)
                }
            }
            HStack {
                Spacer()
                Button("Готово", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
