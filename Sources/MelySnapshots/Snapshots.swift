import SwiftUI
import MelyCore
import MelyUI
import MelyFixtures

struct Snapshot {
    let name: String
    let view: AnyView
}

/// Every state the tasks ask to check visually. Each task adds its entries here.
enum Snapshots {
    /// Behind the island: light gray for checks, clear for the README's desktop.
    @MainActor static var backdrop = Color(white: 0.85)

    /// Pictures for README.md (`mely-snapshots --readme docs/images`): the island on a desktop.
    @MainActor static var readme: [Snapshot] {
        // Views read it when they render: set for the whole --readme run.
        backdrop = .clear
        return [
            Snapshot(name: "icon", view: AnyView(MelyAppIcon().frame(width: 160, height: 160))),
            Snapshot(name: "hero", view: AnyView(Desk { sessionsOverview() })),
            Snapshot(name: "approval", view: AnyView(Desk { requestCard(question: false) })),
            Snapshot(name: "chat", view: AnyView(Desk { chat(hasKey: true, answer: readmeAnswer) })),
            Snapshot(name: "today", view: AnyView(Desk { calendarAgenda() })),
            Snapshot(name: "music", view: AnyView(Desk { miniPlayer() })),
            Snapshot(name: "reminder", view: AnyView(Desk(height: 128) { peekCard(PeekContent(
                id: "r", symbol: "video.fill", tint: .green, title: "Синк по релизу",
                subtitle: "Встреча в Телемосте", appBundleId: "ru.yandex.desktop.telemost", actionTitle: "Подключиться",
                until: Date().addingTimeInterval(4 * 60 + 20))) })),
            Snapshot(name: "update", view: AnyView(Desk(height: 128) { peekCard(PeekContent(
                id: "u", symbol: "arrow.down.circle.fill", tint: .green, title: "Доступна Mely 1.3.0",
                subtitle: "Новая версия готова к установке", actionTitle: "Обновить")) })),
            Snapshot(name: "poses", view: AnyView(Card { allPoses() })),
            Snapshot(name: "wardrobe", view: AnyView(Card { wardrobeSets() })),
        ]
    }

    @MainActor static var all: [Snapshot] {
        let macBook = IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                           auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32)
        let external = IslandScreenGeometry(screenWidth: 2560, safeAreaTop: 0,
                                            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 25)
        return [
            island("Island_Compact_Notch", macBook, .compact),
            island("Island_Expanded_Notch", macBook, .expanded),
            island("Island_Hidden_Notch", macBook, .hidden),
            island("Island_Compact_NoNotch", external, .compact),
            Snapshot(name: "IntegrationsSettings", view: AnyView(
                IntegrationsSettingsView(registry: sampleRegistry(), openPermission: { _ in })
                    .frame(width: 560, height: 520))),
            Snapshot(name: "SettingsChange_Install", view: AnyView(settingsChange())),
            Snapshot(name: "Sessions_Overview", view: AnyView(sessionsOverview())),
            Snapshot(name: "Sessions_One", view: AnyView(sessionsList(1))),
            Snapshot(name: "Sessions_Four", view: AnyView(sessionsList(4))),
            Snapshot(name: "Sessions_Seven", view: AnyView(sessionsList(7))),
            Snapshot(name: "Peek_Finished", view: AnyView(peek())),
            Snapshot(name: "MessagePreview", view: AnyView(messagePreview())),
            Snapshot(name: "CalendarAgenda", view: AnyView(calendarAgenda())),
            Snapshot(name: "NowPlaying_MiniPlayer", view: AnyView(miniPlayer())),
            Snapshot(name: "NowPlaying_Video", view: AnyView(miniPlayerVideo())),
            Snapshot(name: "Island_Compact_Music", view: AnyView(compactMusic())),
            Snapshot(name: "Compact_PlanGauge", view: AnyView(compactPlanGauges())),
            Snapshot(name: "Character_Mely_AllPoses", view: AnyView(allPoses())),
            Snapshot(name: "Character_AllPoses", view: AnyView(speciesPoses())),
            Snapshot(name: "Character_Minimal", view: AnyView(minimalPoses())),
            Snapshot(name: "Wardrobe_Poses", view: AnyView(wardrobePoses())),
            Snapshot(name: "Wardrobe_Sets", view: AnyView(wardrobeSets())),
            Snapshot(name: "CharacterCustomization", view: AnyView(customVariants())),
            Snapshot(name: "CharacterGallery", view: AnyView(characterSettings())),
            Snapshot(name: "Settings_General", view: AnyView(generalSettings())),
            Snapshot(name: "Launch_Frames", view: AnyView(launchFrames())),
            Snapshot(name: "Character_Quirks", view: AnyView(quirks())),
            Snapshot(name: "Layout_LongTexts", view: AnyView(longTexts())),
            Snapshot(name: "PlanUsage_Card", view: AnyView(usageCard())),
            Snapshot(name: "Island_Expanded_NoNotch", view: AnyView(expandedNoNotch())),
            Snapshot(name: "MeetingReminder", view: AnyView(peekCard(PeekContent(
                id: "r", symbol: "video.fill", tint: .green, title: "Синк по релизу",
                subtitle: "Встреча в Телемост", appBundleId: "ru.yandex.desktop.telemost", actionTitle: "Подключиться",
                until: Date().addingTimeInterval(4 * 60 + 20))))),
            Snapshot(name: "MeetingJoin", view: AnyView(peekCard(PeekContent(
                id: "j", symbol: "doc.on.clipboard", tint: .gray, title: "Ссылка на встречу скопирована",
                subtitle: "Если Телемост не открыл встречу: Подключиться → ⌘V", appBundleId: "ru.yandex.desktop.telemost")))),
            Snapshot(name: "Update_Peek", view: AnyView(peekCard(PeekContent(
                id: "update-available-1.3.0", symbol: "arrow.down.circle.fill", tint: .green, title: "Доступна Mely 1.3.0",
                subtitle: "Новая версия готова к установке", actionTitle: "Обновить")))),
            Snapshot(name: "Update_Done", view: AnyView(peekCard(PeekContent(
                id: "updated-1.3.0", symbol: "sparkles", tint: .green, title: "Обновилась до 1.3.0",
                subtitle: "Посмотрите, что изменилось", actionTitle: "Что нового")))),
            Snapshot(name: "Update_HeaderDot", view: AnyView(
                header(selected: .sessions, updateAvailable: true).frame(width: 760, height: 34).background(.black))),
            Snapshot(name: "Update_Pill", view: AnyView(expandedApp(.sessions, updateAvailable: true) {
                Fixtures.sessionsPage(SessionStore())
            })),
            Snapshot(name: "Update_PillAway", view: AnyView(expandedApp(.sessions, updateAvailable: true) {
                Fixtures.sessionsPage(SessionStore())
            }.environment(\.characterDrag, CharacterDrag(isAway: true, began: { _ in }, moved: { _ in }, ended: { _ in },
                                                          callHome: {})))),
            Snapshot(name: "Settings_Updates", view: AnyView(updateSettings())),
            Snapshot(name: "Messages_Tab", view: AnyView(messagesTab())),
            Snapshot(name: "PlanUsageGauge", view: AnyView(planUsage())),
            Snapshot(name: "Chat_Answer", view: AnyView(chat(hasKey: true))),
            Snapshot(name: "Chat_NoKey", view: AnyView(chat(hasKey: false))),
            Snapshot(name: "Chat_ModelPicker", view: AnyView(modelPicker())),
            Snapshot(name: "MenuBarIcon", view: AnyView(menuBarIcon())),
            Snapshot(name: "AppIcon", view: AnyView(MelyAppIcon().frame(width: 512, height: 512))),
            Snapshot(name: "ApprovalCard", view: AnyView(requestCard(question: false))),
            Snapshot(name: "QuestionCard_Multi", view: AnyView(requestCard(question: true))),
        ]
    }

    static let canvasLooks = [BuiltInLooks.mely, BuiltInLooks.fawn, BuiltInLooks.lamb, BuiltInLooks.conure, BuiltInLooks.fox]

    @MainActor private static func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.7))
    }

    /// Every Canvas character in every pose (task 6.2).
    @MainActor private static func speciesPoses() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 80, height: 1)
                ForEach(CharacterPose.allCases, id: \.self) { label($0.title).frame(width: 84) }
            }
            ForEach(canvasLooks) { look in
                HStack(spacing: 8) {
                    label(look.title).frame(width: 80, alignment: .leading)
                    ForEach(CharacterPose.allCases, id: \.self) { pose in
                        MelyCharacterFrame(pose: pose, gaze: CGPoint(x: 0.5, y: 0.3), time: pose == .happy ? 0.28 : 0.6,
                                           appearance: CharacterAppearance(lookId: look.id, values: look.values([:])))
                            .frame(width: 84, height: 84)
                    }
                }
            }
            HStack(spacing: 8) {
                label("Кружится").frame(width: 80, alignment: .leading)
                ForEach(canvasLooks) { look in
                    MelyCharacterFrame(pose: .idle, time: 0.6, appearance: CharacterAppearance(lookId: look.id, values: look.values([:])),
                                       dizzy: true)
                        .frame(width: 84, height: 84)
                }
            }
            HStack(spacing: 8) {
                label("В челке").frame(width: 80, alignment: .leading)
                ForEach(canvasLooks) { look in
                    MelyCharacterFrame(pose: .idle, appearance: CharacterAppearance(lookId: look.id, values: look.values([:])))
                        .frame(width: 26, height: 26)
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    @MainActor private static func minimalPoses() -> some View {
        HStack(spacing: 14) {
            ForEach(CharacterPose.allCases, id: \.self) { pose in
                VStack(spacing: 6) {
                    MelyCharacterFrame(pose: pose, appearance: CharacterAppearance(lookId: "minimal")).frame(width: 40, height: 40)
                    MelyCharacterFrame(pose: pose, appearance: CharacterAppearance(lookId: "minimal")).frame(width: 22, height: 22)
                    label(pose.title)
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// A hat and glasses in every pose, on one character (task 6.10).
    @MainActor private static func wardrobePoses() -> some View {
        let outfit: [AccessorySlot: Accessory] = [.head: .beanie, .eyes: .roundGlasses, .neck: .stripedScarf, .held: .wand]
        return VStack(alignment: .leading, spacing: 10) {
            ForEach([BuiltInLooks.lamb, BuiltInLooks.fox], id: \.id) { look in
                HStack(spacing: 8) {
                    ForEach(CharacterPose.allCases, id: \.self) { pose in
                        VStack(spacing: 4) {
                            MelyCharacterFrame(pose: pose, gaze: CGPoint(x: -0.4, y: 0.2), time: 0.6,
                                               appearance: CharacterAppearance(lookId: look.id, values: look.values([:]), outfit: outfit))
                                .frame(width: 84, height: 84)
                            label(pose.title)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// Every character in every set, and every single thing (task 6.11).
    @MainActor private static func wardrobeSets() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(OutfitSet.allCases) { set in
                HStack(spacing: 10) {
                    label(set.title).frame(width: 80, alignment: .leading)
                    ForEach(canvasLooks) { look in
                        MelyCharacterFrame(pose: .idle, gaze: CGPoint(x: 0.3, y: 0.2), time: 0.6,
                                           appearance: CharacterAppearance(lookId: look.id, values: look.values([:]), outfit: set.outfit))
                            .frame(width: 96, height: 96)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(Accessory.allCases) { item in
                    VStack(spacing: 2) {
                        MelyCharacterFrame(pose: .idle, time: 0.6,
                                           appearance: CharacterAppearance(lookId: "mely", values: BuiltInLooks.mely.values([:]),
                                                                           outfit: [item.slot: item]))
                            .frame(width: 60, height: 60)
                        Text(item.title).font(.system(size: 8)).foregroundStyle(.white.opacity(0.6)).frame(width: 60).lineLimit(2)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// Mely's extras (task 7.5): a wink, the tickle of a poke, confetti on a special day.
    @MainActor private static func quirks() -> some View {
        HStack(spacing: 16) {
            ForEach([("Подмигивает", Reaction.wink), ("Тык: сердечки", .poke), ("Пятница!", .party)], id: \.0) { item in
                VStack(spacing: 4) {
                    MelyCharacterFrame(pose: .idle, gaze: CGPoint(x: 0.3, y: 0), time: 1000.2, reaction: item.1)
                        .frame(width: 96, height: 96)
                    label(item.0)
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// The launch greeting at a few moments (task 7.2).
    @MainActor private static func launchFrames() -> some View {
        VStack(spacing: 6) {
            ForEach([0.35, 0.55, 0.72, 1.0, 1.6, 2.2], id: \.self) { t in
                HStack(spacing: 8) {
                    label(String(format: "%.2f с", t)).frame(width: 50)
                    let p = IslandPresentation(geometry: IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                               auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32))
                    let _ = { p.mode = .greeting; p.greetingStart = Date().addingTimeInterval(-t) }()
                    IslandRootView(presentation: p, compactLeading: { EmptyView() }, compactTrailing: AnyView(EmptyView()),
                                   expanded: { EmptyView() })
                        .frame(width: 760, height: 150, alignment: .top).clipped()
                }
            }
        }
        .padding(10)
        .background(backdrop)
    }

    /// Settings → Основные (task 7.11).
    @MainActor private static func generalSettings() -> some View {
        let defaults = UserDefaults(suiteName: "mely-snapshots-general")!
        defaults.removePersistentDomain(forName: "mely-snapshots-general")
        let behavior = IslandBehavior(defaults: defaults)
        behavior.collapseAfter = IslandBehavior.never
        return GeneralSettingsView(behavior: behavior,
                                   sounds: .init(test: {}, openFolder: {}, reload: { 2 }, customized: 2),
                                   launchAtLogin: .constant(true), peeks: Fixtures.peeks(), displayChanged: {})
            .frame(width: 560, height: 980)
    }

    /// Settings → Основные → Обновления in each state, and a long local version.
    @MainActor private static func updateSettings() -> some View {
        let phases: [(String, UpdateState.Phase)] = [("1.2.0", .upToDate), ("1.2.0", .available(version: "1.3.0")),
                                                     ("1.2.0", .checking), ("10.20.300-dev", .failed)]
        return VStack(spacing: 0) {
            ForEach(Array(phases.enumerated()), id: \.offset) { _, item in
                let state = UpdateState(currentVersion: item.0, releasesURL: URL(string: "https://github.com"))
                let _ = { state.phase = item.1 }()
                Form { UpdatesSection(updates: state) }.formStyle(.grouped).frame(height: 150)
            }
        }
        .frame(width: 560)
    }

    /// Settings → Персонаж with the gallery, a look's options and the wardrobe (6.5, 6.10).
    @MainActor private static func characterSettings() -> some View {
        let defaults = UserDefaults(suiteName: "mely-snapshots-character")!
        defaults.removePersistentDomain(forName: "mely-snapshots-character")
        let settings = CharacterSettings(defaults: defaults)
        settings.dressesBySeason = false
        settings.select("fox")
        settings.wear(.headphones, in: .head, for: "fox")
        settings.setHidden("lamb", true)
        return CharacterSettingsView(settings: settings)
            .frame(width: 600, height: 980)
    }

    /// Each customization option switched away from its default (task 6.5).
    @MainActor private static func customVariants() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(canvasLooks) { look in
                HStack(spacing: 8) {
                    label(look.title).frame(width: 80, alignment: .leading)
                    ForEach(variants(look), id: \.0) { name, values in
                        VStack(spacing: 2) {
                            MelyCharacterFrame(pose: .idle, time: 0.6, appearance: CharacterAppearance(lookId: look.id, values: values))
                                .frame(width: 70, height: 70)
                            Text(name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.black)
    }

    static func variants(_ look: CharacterLook) -> [(String, [String: CustomizationValue])] {
        var list: [(String, [String: CustomizationValue])] = [("как есть", look.values([:]))]
        for option in look.customizations {
            switch option.kind {
            case .color(let palette):
                for c in palette.dropFirst() { list.append((option.title + " " + c, look.values([option.id: .color(c)]))) }
            case .toggle:
                list.append(("без: " + option.title, look.values([option.id: .bool(false)])))
            case .choice(let choices):
                for c in choices.dropFirst() { list.append((c.title, look.values([option.id: .choice(c.id)]))) }
            case .number:
                break
            }
        }
        return list
    }

    /// Every pose, large, with its name; and how small it really is in the notch.
    @MainActor private static func allPoses() -> some View {
        let columns = Array(repeating: GridItem(.fixed(150), spacing: 18), count: 3)
        return VStack(spacing: 18) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(CharacterPose.allCases, id: \.self) { pose in
                    VStack(spacing: 6) {
                        MelyCharacterFrame(pose: pose, gaze: CGPoint(x: 0.6, y: 0.3), time: pose == .happy ? 0.28 : 0.6)
                            .frame(width: 120, height: 120)
                        Text(pose.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            HStack(spacing: 14) {
                Text("Взгляд:").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                ForEach([CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)], id: \.x) { g in
                    MelyCharacterFrame(pose: .working, gaze: g).frame(width: 60, height: 60)
                }
                ForEach([CGPoint(x: -1, y: 0.2), CGPoint(x: 1, y: 0.2)], id: \.x) { g in
                    MelyCharacterFrame(pose: .idle, gaze: g).frame(width: 26, height: 26)
                }
            }
            HStack(spacing: 14) {
                Text("В челке:").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                ForEach(CharacterPose.allCases, id: \.self) { pose in
                    MelyCharacterFrame(pose: pose, time: pose == .happy ? 0.28 : 0.6).frame(width: 26, height: 26)
                }
            }
        }
        .padding(24)
        .background(Color.black)
    }

    /// The compact island while music plays and Claude works: cover left, bars and limit right.
    @MainActor private static func compactMusic() -> some View {
        let model = NowPlayingModel()
        let cover = NSImage(size: NSSize(width: 60, height: 60), flipped: false) { rect in
            NSGradient(colors: [.systemPurple, .systemOrange])?.draw(in: rect, angle: 45)
            return true
        }
        let png = cover.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        model.update(NowPlaying(bundleId: "ru.yandex.desktop.music", parentBundleId: nil, title: "Песня", artist: nil,
                                album: nil, duration: 200, elapsed: 10, timestamp: Date(), isPlaying: true, rate: 1,
                                artwork: png, prohibitsSkip: false))
        let store = SessionStore()
        store.apply(.userPrompt("корзина"), origin: HookOrigin(["session_id": "a", "cwd": "/w/shop",
                                                                 "host_bundle_id": "com.jetbrains.WebStorm"]))
        let defaults = UserDefaults(suiteName: "mely-snapshots-compact")!
        defaults.removePersistentDomain(forName: "mely-snapshots-compact")
        let usage = PlanUsageStore(defaults: defaults)
        usage.update(rateLimits: ["five_hour": ["used_percentage": 64, "resets_at": Date().timeIntervalSince1970 + 3600]])
        let p = IslandPresentation(geometry: IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                   auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32))
        p.mode = .compact
        return IslandRootView(presentation: p, compactLeading: { CompactLeading(music: model) },
                              compactTrailing: AnyView(CompactSessionStatus(store: store, usage: usage, music: model)),
                              expanded: { EmptyView() })
            .frame(height: 70, alignment: .top).clipped()
            .background(backdrop)
    }

    /// The compact limit: 30% of five hours (the week at 85% stays out), five hours used
    /// up, the week used up.
    @MainActor private static func compactPlanGauges() -> some View {
        let now = Date()
        func usage(_ five: Double, _ week: Double) -> PlanUsage {
            PlanUsage(fiveHour: PlanWindow(usedPercent: five, resetsAt: now.addingTimeInterval(80 * 60)),
                      sevenDay: PlanWindow(usedPercent: week, resetsAt: now.addingTimeInterval(2 * 86400 + 5 * 3600)),
                      updatedAt: now)
        }
        return HStack(spacing: 24) {
            ForEach(Array([(30.0, 85.0), (100, 70), (10, 100)].enumerated()), id: \.offset) { _, pair in
                CompactPlanGauge(usage: usage(pair.0, pair.1))
                    .padding(.horizontal, 7).frame(height: 22)
                    .background(.white.opacity(0.07), in: Capsule())
            }
        }
        .padding(20)
        .background(Color.black)
    }

    /// Yandex Music playing, a minute into the track, with a generated cover.
    /// A browser video: a 16:9 cover, a long title, no artist, a live stream without duration.
    @MainActor private static func miniPlayerVideo() -> some View {
        let model = NowPlayingModel()
        let cover = NSImage(size: NSSize(width: 480, height: 270), flipped: false) { rect in
            NSGradient(colors: [.systemTeal, .systemIndigo])?.draw(in: rect, angle: 0)
            return true
        }
        let png = cover.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        model.update(NowPlaying(bundleId: "com.google.Chrome", parentBundleId: nil,
                                title: "Как устроены часы: полный разбор механизма за 40 минут — от анкера до турбийона",
                                artist: nil, album: nil, duration: nil, elapsed: 600, timestamp: Date(),
                                isPlaying: true, rate: 1, artwork: png, prohibitsSkip: true))
        let tabs = IslandTabs()
        tabs.selected = .music
        return expandedApp(.music, pose: .dancing) {
            ClaudeOverview(store: SessionStore(), queue: ApprovalQueue(), tabs: tabs,
                           music: AnyView(MiniPlayerView(model: model, send: { _ in }, openSource: { _ in })),
                           open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
        }
    }

    @MainActor private static func miniPlayer() -> some View {
        let model = NowPlayingModel()
        let cover = NSImage(size: NSSize(width: 200, height: 200), flipped: false) { rect in
            NSGradient(colors: [.systemPurple, .systemOrange])?.draw(in: rect, angle: 45)
            return true
        }
        let png = cover.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
        model.update(NowPlaying(bundleId: "ru.yandex.desktop.music", parentBundleId: nil, title: "Тёплый вечер",
                                artist: "Лампа и кот", album: nil, duration: 158, elapsed: 62, timestamp: Date(),
                                isPlaying: true, rate: 1, artwork: png, prohibitsSkip: false))
        let tabs = IslandTabs()
        tabs.selected = .music
        return expandedApp(.music, pose: .dancing) {
            ClaudeOverview(store: SessionStore(), queue: ApprovalQueue(), tabs: tabs,
                           music: AnyView(MiniPlayerView(model: model, send: { _ in }, openSource: { _ in })),
                           open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
        }
    }

    /// Any preview under the notch.
    @MainActor private static func peekCard(_ content: PeekContent) -> some View {
        let p = IslandPresentation(geometry: IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                   auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32))
        p.peek = content
        p.mode = .peek
        p.dismissPeek = {}
        return IslandRootView(presentation: p, compactLeading: { EmptyView() }, compactTrailing: AnyView(EmptyView()),
                              expanded: { EmptyView() })
            .frame(height: 200, alignment: .top).clipped()
            .background(backdrop)
    }

    /// The "Сегодня" tab mid-morning: an all-day event, one past, one running with a call.
    @MainActor private static func calendarAgenda() -> some View {
        let now = Date()
        func ev(_ id: String, _ title: String, _ from: Double, _ to: Double, allDay: Bool = false,
                location: String? = nil, meeting: MeetingLink? = nil) -> CalendarEvent {
            CalendarEvent(id: id, title: title, start: now.addingTimeInterval(from * 60), end: now.addingTimeInterval(to * 60),
                          isAllDay: allDay, location: location, meeting: meeting)
        }
        let telemost = MeetingLink(service: .telemost, url: URL(string: "https://telemost.yandex.ru/j/5512")!)
        let zoom = MeetingLink(service: .zoom, url: URL(string: "https://zoom.us/j/831")!)
        let agenda = Agenda(today: [
            ev("d", "Дежурство по релизу", -600, 800, allDay: true),
            ev("a", "Стендап", -120, -105, meeting: telemost),
            ev("b", "Синк по корзине", -10, 35, meeting: telemost),
            ev("c", "Интервью фронтенд", 12, 72, meeting: zoom),
            ev("e", "Обед", 120, 180, location: "Кафе на первом"),
        ], tomorrow: [])
        let tabs = IslandTabs()
        tabs.selected = .today
        return expandedApp(.today) {
            ClaudeOverview(store: SessionStore(), queue: ApprovalQueue(), tabs: tabs,
                           today: AnyView(AgendaView(agenda: agenda) { _ in }),
                           open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
        }
    }

    /// A Telegram message under the notch, as the mirror shows it.
    @MainActor private static func messagePreview() -> some View {
        let p = IslandPresentation(geometry: IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                   auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32))
        p.peek = PeekContent(id: "m", symbol: "bell.fill", tint: .blue, title: "Аня Смирнова",
                             subtitle: "Созвон переносим на 15:30, ссылку кину в чат", appBundleId: "ru.keepcoder.Telegram",
                             opensApp: true)
        p.mode = .peek
        return IslandRootView(presentation: p, compactLeading: { EmptyView() }, compactTrailing: AnyView(EmptyView()),
                              expanded: { EmptyView() })
            .background(backdrop)
    }

    /// The overview's messages tab with a few mirrored notifications and an unseen count.
    @MainActor private static func messagesTab() -> some View {
        let messages = MirroredMessages()
        let now = Date()
        let sample: [(String, String, String, TimeInterval)] = [
            ("com.google.Chrome", "Новый заказ", "shop.ru — Заказ №42 оплачен", 1500),
            ("com.anthropic.claudefordesktop", "Claude", "Готов план миграции на Swift 6: три шага…", 600),
            ("ru.keepcoder.Telegram", "Аня Смирнова", "Созвон переносим на 15:30", 60),
        ]
        for (i, s) in sample.enumerated() {
            let n = MirroredNotification(id: Int64(i), bundleId: s.0, title: s.1, subtitle: nil, body: s.2,
                                         deliveredAt: now.addingTimeInterval(-s.3))
            messages.add(n, appName: s.1, title: s.1, text: s.2)
        }
        let tabs = IslandTabs()
        tabs.selected = .messages
        return expandedApp(.messages) {
            ClaudeOverview(store: SessionStore(), queue: ApprovalQueue(), tabs: tabs,
                           messages: AnyView(MessagesView(messages: messages) { (_: Int64) in }),
                           open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
        }
    }

    /// Long names and texts everywhere: nothing may push the layout (task 7.10).
    @MainActor private static func longTexts() -> some View {
        let store = SessionStore()
        let long = HookOrigin(["session_id": "a", "cwd": "/w/очень-длинное-название-проекта-для-проверки-вёрстки-челки",
                               "host_bundle_id": "com.jetbrains.WebStorm"])
        store.apply(.userPrompt("x"), origin: long)
        store.apply(.toolStarted(tool: "Bash", input: JSONObject(["command": "npm run build && npm run test -- --coverage --reporter=verbose --runInBand --detectOpenHandles"])), origin: long)
        let other = HookOrigin(["session_id": "b", "cwd": "/w/api", "term_program": "iTerm.app"])
        store.apply(.stop(lastMessage: "Готово: эндпоинт /orders теперь возвращает пагинацию, фильтры по статусу и дате, а ещё я переписал все тесты на новый формат и обновил документацию в README."), origin: other)
        let tabs = IslandTabs()
        return expandedApp(.sessions, pose: .working) {
            ClaudeOverview(store: store, queue: ApprovalQueue(), tabs: tabs, open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
        }
    }

    /// The sessions tab with its limits row, and the pill's card open (the limits by name).
    @MainActor private static func usageCard() -> some View {
        let store = SessionStore()
        store.apply(.userPrompt("x"), origin: HookOrigin(["session_id": "a", "cwd": "/w/shop", "host_bundle_id": "com.jetbrains.WebStorm"]))
        let defaults = UserDefaults(suiteName: "mely-snapshots-usage")!
        defaults.removePersistentDomain(forName: "mely-snapshots-usage")
        let usage = PlanUsageStore(defaults: defaults)
        let now = Date().timeIntervalSince1970
        usage.update(rateLimits: ["five_hour": ["used_percentage": 42, "resets_at": now + 2 * 3600 + 14 * 60],
                                  "seven_day": ["used_percentage": 86, "resets_at": now + 3 * 86400 + 4 * 3600]])
        let tabs = IslandTabs()
        return VStack(spacing: 10) {
            expandedApp(.sessions, pose: .working) {
                ClaudeOverview(store: store, queue: ApprovalQueue(), usage: usage, tabs: tabs,
                               open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
            }
            expandedApp(.sessions, showsUsage: true, pose: .working) {
                ClaudeOverview(store: store, queue: ApprovalQueue(), usage: usage, tabs: tabs,
                               open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
            }
        }
    }

    /// An external screen without a notch: the header still clears the resting bar.
    @MainActor private static func expandedNoNotch() -> some View {
        let store = SessionStore()
        store.apply(.userPrompt("x"), origin: HookOrigin(["session_id": "a", "cwd": "/w/shop", "host_bundle_id": "com.jetbrains.WebStorm"]))
        let tabs = IslandTabs()
        return expandedApp(.sessions, geometry: IslandScreenGeometry(screenWidth: 2560, safeAreaTop: 0, auxiliaryLeftWidth: nil,
                                                                     auxiliaryRightWidth: nil, menuBarHeight: 25), pose: .working) {
            ClaudeOverview(store: store, queue: ApprovalQueue(), tabs: tabs, open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
        }
    }

    @MainActor private static func peek() -> some View {
        let p = IslandPresentation(geometry: IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                   auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32))
        p.peek = PeekContent(id: "x", symbol: "checkmark", tint: .green, title: "Готово · shop",
                             subtitle: "Корзина пересчитывает скидки, тесты зелёные.", appBundleId: "com.jetbrains.WebStorm")
        p.mode = .peek
        return IslandRootView(presentation: p, compactLeading: { EmptyView() }, compactTrailing: AnyView(EmptyView()),
                              expanded: { EmptyView() })
            .background(backdrop)
    }

    /// Overview with both windows (the weekly one past 80%), and the compact island warning.
    @MainActor private static func planUsage() -> some View {
        let store = SessionStore()
        store.apply(.userPrompt("корзина"), origin: HookOrigin(["session_id": "a", "cwd": "/w/shop",
                                                                 "host_bundle_id": "com.jetbrains.WebStorm"]))
        let defaults = UserDefaults(suiteName: "mely-snapshots-plan")!
        defaults.removePersistentDomain(forName: "mely-snapshots-plan")
        let usage = PlanUsageStore(defaults: defaults)
        let now = Date().timeIntervalSince1970
        usage.update(rateLimits: ["five_hour": ["used_percentage": 42, "resets_at": now + 2 * 3600 + 14 * 60],
                                  "seven_day": ["used_percentage": 86, "resets_at": now + 3 * 86400 + 4 * 3600]])
        func island(_ mode: IslandPresentation.Mode) -> some View {
            let p = IslandPresentation(geometry: IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                       auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32))
            p.mode = mode
            return IslandRootView(presentation: p, compactLeading: { Circle().fill(Color.orange) },
                                  compactTrailing: AnyView(CompactSessionStatus(store: store, usage: usage)),
                                  expanded: { SessionsOverview(store: store, usage: usage) { _ in } })
        }
        /// Compact island at a given 5-hour level.
        func compact(_ percent: Double) -> some View {
            let level = PlanUsageStore(defaults: defaults)
            level.update(rateLimits: ["five_hour": ["used_percentage": percent, "resets_at": now + 3600],
                                      "seven_day": ["used_percentage": 20, "resets_at": now + 86400]])
            let p = IslandPresentation(geometry: IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                       auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32))
            p.mode = .compact
            return IslandRootView(presentation: p, compactLeading: { Circle().fill(Color.orange) },
                                  compactTrailing: AnyView(CompactSessionStatus(store: store, usage: level)),
                                  expanded: { EmptyView() })
                .frame(height: 60, alignment: .top).clipped()
        }
        return VStack(spacing: 0) {
            island(.expanded)
            compact(23); compact(64); compact(84); compact(93); compact(100)
        }
        .background(backdrop)
    }

    /// The model popover as it opens from the dark island.
    @MainActor private static func modelPicker() -> some View {
        let defaults = UserDefaults(suiteName: "mely-snapshots-picker")!
        defaults.removePersistentDomain(forName: "mely-snapshots-picker")
        let preferences = ChatPreferences(defaults: defaults)
        preferences.claudeFound = true
        return ChatModelPicker(preferences: preferences, openSettings: {}, close: {})
            .frame(width: 300)
            .background(Color(white: 0.12))
            .environment(\.colorScheme, .dark)
    }

    /// Short enough for the README picture to show the whole conversation.
    static let readmeAnswer = "Скорее всего, скидка считается **до** округления. Округляйте цену позиции "
        + "в `CartItem.total`, а скидку применяйте к сумме корзины."

    /// The chat tab after one question with a screenshot attached, or without a key.
    @MainActor private static func chat(hasKey: Bool, answer: String? = nil) -> some View {
        let transport: ChatTransport = answer.map { FixtureChatTransport(answer: $0) } ?? SampleChatTransport()
        let conversation = ChatConversation(transport: transport,
                                            apiKey: { hasKey ? "k" : nil }, model: { .opus })
        let defaults = UserDefaults(suiteName: "mely-snapshots-chat")!
        defaults.removePersistentDomain(forName: "mely-snapshots-chat")
        let preferences = ChatPreferences(defaults: defaults)
        preferences.claudeFound = true
        if hasKey {
            conversation.offer(context: ChatContext(appName: "Safari", windowTitle: "Корзина — shop",
                                                    url: "https://shop.example.ru/cart"))
            let shot = FileManager.default.temporaryDirectory.appendingPathComponent("Снимок экрана.png")
            try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: shot)
            conversation.attach([shot])
            conversation.send("Почему в корзине копейки не сходятся?")
            // Let the sample stream arrive before the picture is taken.
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        let tabs = IslandTabs()
        tabs.selected = .chat
        return expandedApp(.chat, pose: hasKey ? .happy : .idle) {
            ClaudeOverview(store: SessionStore(), queue: ApprovalQueue(), tabs: tabs,
                           chat: AnyView(ChatView(conversation: conversation, preferences: preferences, tabs: tabs, openSettings: {})),
                           open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
        }
    }

    /// The template icon as macOS tints it: light and dark menu bar, real size and zoomed.
    @MainActor private static func menuBarIcon() -> some View {
        let icon = Image(nsImage: MelyLogo.menuBarImage()).renderingMode(.template)
        func bar(_ background: Color, _ ink: Color) -> some View {
            HStack(spacing: 18) {
                Image(systemName: "wifi"); Image(systemName: "battery.75percent")
                icon.frame(width: 18, height: 18)
                Text("Пн 19 окт. 11:40").font(.system(size: 13, weight: .medium))
                icon.resizable().interpolation(.none).frame(width: 72, height: 72)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 16).frame(height: 96)
            .background(background)
        }
        return VStack(spacing: 0) {
            bar(Color(white: 0.93), .black.opacity(0.85))
            bar(Color(white: 0.12), .white)
        }
    }

    /// A WebStorm session asking, with a second request queued behind it.
    @MainActor private static func requestCard(question: Bool) -> some View {
        let store = SessionStore()
        let queue = ApprovalQueue()
        let ws = HookOrigin(["session_id": "a", "cwd": "/w/shop", "host_bundle_id": "com.jetbrains.WebStorm"])
        let event: HookEvent = question
            ? .question(input: JSONObject(["questions": [
                ["question": "Какую библиотеку валидации взять?", "header": "Библиотека", "multiSelect": false,
                 "options": [["label": "zod", "description": "Типы выводятся из схем"],
                             ["label": "yup", "description": "Уже есть в admin"]]],
                ["question": "Что покрыть тестами?", "header": "Тесты", "multiSelect": true,
                 "options": [["label": "Корзину"], ["label": "Оплату"], ["label": "Доставку"]]],
            ]]))
            : .permissionRequest(tool: "Bash", input: JSONObject(["command": "npm run build && npm run test -- --coverage"]),
                                 suggestions: JSONObject(["items": [["type": "addRules"]]]))
        queue.enqueue(event, session: store.apply(event, origin: ws)!, responder: SampleResponder.make())
        let admin = HookOrigin(["session_id": "b", "cwd": "/w/admin", "term_program": "iTerm.app"])
        let second: HookEvent = .permissionRequest(tool: "Edit", input: JSONObject(["file_path": "/w/admin/app.ts"]),
                                                   suggestions: JSONObject([:]))
        queue.enqueue(second, session: store.apply(second, origin: admin)!, responder: SampleResponder.make())
        return expandedApp(.sessions, held: true, pose: question ? .curious : .worried) {
            ClaudeOverview(store: store, queue: queue, open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
        }
    }

    @MainActor private static func sessionsOverview() -> some View {
        let store = SessionStore()
        let ws = HookOrigin(["session_id": "a", "cwd": "/w/shop", "host_bundle_id": "com.jetbrains.WebStorm"])
        store.apply(.userPrompt("корзина"), origin: ws)
        store.apply(.toolStarted(tool: "Edit", input: JSONObject(["file_path": "/w/shop/Cart.tsx"])), origin: ws)
        store.apply(.toolFinished(tool: "Edit", input: JSONObject(["file_path": "/w/shop/Cart.tsx", "old_string": "a\nb", "new_string": "a\nc\nd"]), failed: false), origin: ws)
        let admin = HookOrigin(["session_id": "b", "cwd": "/w/admin", "host_bundle_id": "com.jetbrains.WebStorm"])
        store.apply(.permissionRequest(tool: "Bash", input: JSONObject(["command": "npm run build"]), suggestions: JSONObject([:])), origin: admin)
        let term = HookOrigin(["session_id": "c", "cwd": "/w/api", "term_program": "iTerm.app"])
        store.apply(.stop(lastMessage: "Готово: эндпоинт /orders возвращает пагинацию."), origin: term)
        let p = IslandPresentation(geometry: IslandScreenGeometry(screenWidth: 1512, safeAreaTop: 32,
                                   auxiliaryLeftWidth: 660, auxiliaryRightWidth: 660, menuBarHeight: 32))
        p.mode = .expanded
        return IslandRootView(presentation: p, compactLeading: { EmptyView() },
                              compactTrailing: AnyView(CompactSessionStatus(store: store)),
                              expanded: {
                                  // As the app lays it out: the big Mely left, a little Mely per session.
                                  HStack(alignment: .top, spacing: 12) {
                                      MelyStage(pose: .worried).frame(width: 88).padding(.top, 2)
                                      // Through the overview, as the app does: the island fits the page.
                                      ClaudeOverview(store: store, queue: ApprovalQueue(), tabs: IslandTabs(),
                                                     open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
                                  }
                              },
                              header: { Self.header(selected: .sessions) })
            .background(backdrop)
    }

    /// The sessions page with `count` working sessions: how tall the island gets.
    @MainActor private static func sessionsList(_ count: Int) -> some View {
        let store = SessionStore()
        let names = ["shop", "admin", "api", "docs", "mobile", "billing", "infra"]
        for name in names.prefix(count) {
            store.apply(.toolStarted(tool: "Edit", input: JSONObject(["file_path": "/w/\(name)/index.ts"])),
                        origin: HookOrigin(["session_id": name, "cwd": "/w/\(name)", "host_bundle_id": "com.jetbrains.WebStorm"]))
        }
        let defaults = UserDefaults(suiteName: "mely-snapshots-sessions")!
        defaults.removePersistentDomain(forName: "mely-snapshots-sessions")
        let usage = PlanUsageStore(defaults: defaults)
        usage.update(rateLimits: ["five_hour": ["used_percentage": 56, "resets_at": Date().timeIntervalSince1970 + 7200]])
        return expandedApp(.sessions, pose: .working) {
            ClaudeOverview(store: store, queue: ApprovalQueue(), usage: usage, tabs: IslandTabs(),
                           open: { _ in }, decide: { _, _ in }, answerInTerminal: { _ in })
        }
    }

    /// The expanded island as the app lays it out (`Fixtures.expandedApp`) on this run's backdrop.
    @MainActor static func expandedApp<C: View>(_ tab: IslandTabs.Tab, geometry: IslandScreenGeometry? = nil,
                                                held: Bool = false, showsUsage: Bool = false, pose: CharacterPose = .idle,
                                                updateAvailable: Bool = false,
                                                @ViewBuilder content: () -> C) -> some View {
        Fixtures.expandedApp(tab, geometry: geometry, held: held, showsUsage: showsUsage, pose: pose,
                             updateAvailable: updateAvailable, backdrop: backdrop, content: content)
    }

    @MainActor static func header(selected: IslandTabs.Tab, held: Bool = false, showsUsage: Bool = false,
                                  updateAvailable: Bool = false) -> IslandHeader {
        Fixtures.header(selected: selected, held: held, showsUsage: showsUsage, updateAvailable: updateAvailable)
    }

    @MainActor private static func settingsChange() -> some View {
        let before = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        let object = (try? JSONSerialization.jsonObject(with: Data(before.utf8))) as? [String: Any] ?? [:]
        let after = (try? ClaudeHookInstaller.installing(into: object, relayPath: "/Users/me/.mely/bin/nc-hook")) ?? [:]
        let old = String(decoding: (try? ClaudeHookInstaller.encode(object)) ?? Data(), as: UTF8.self)
        let new = String(decoding: (try? ClaudeHookInstaller.encode(after)) ?? Data(), as: UTF8.self)
        let change = PendingSettingsChange(title: "Подключить Claude Code", diff: LineDiff.text(from: old, to: new),
                                           newData: Data(), originalBytes: nil)
        return SettingsChangeView(change: change,
                                  error: nil, onApply: {}, onCancel: {})
    }

    @MainActor private static func island(_ name: String, _ geometry: IslandScreenGeometry,
                                          _ mode: IslandPresentation.Mode) -> Snapshot {
        let p = IslandPresentation(geometry: geometry)
        p.mode = mode
        let view = IslandRootView(
            presentation: p,
            compactLeading: { Circle().fill(Color.orange) },
            compactTrailing: AnyView(Text("shop").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)),
            expanded: { Text("Обзор").foregroundStyle(.white) })
        // Menu-bar-like backdrop so the ears are visible.
        return Snapshot(name: name, view: AnyView(view.background(backdrop)))
    }
}


/// A slice of a Mac desktop under the notch: a soft wallpaper with the island on top.
private struct Desk<Content: View>: View {
    var height: CGFloat = 330
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.29, green: 0.33, blue: 0.62), Color(red: 0.62, green: 0.45, blue: 0.72),
                                    Color(red: 0.95, green: 0.66, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.25), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 520)
            content().frame(height: height, alignment: .top).clipped()
        }
        .frame(width: 760, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(1)
    }
}

/// A dark card for the character sheets.
private struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background(Color(white: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(1)
    }
}
