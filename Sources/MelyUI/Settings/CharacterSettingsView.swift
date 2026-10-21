import SwiftUI
import MelyCore

/// Settings → Персонаж: the gallery of looks, the chosen look's settings and clothes
/// (tasks 6.5, 6.10, 6.11).
public struct CharacterSettingsView: View {
    let settings: CharacterSettings

    @State private var showHidden = false
    @State private var preview: CharacterPose = .idle

    public init(settings: CharacterSettings) {
        self.settings = settings
    }

    public var body: some View {
        let look = settings.look
        Form {
            Section {
                gallery
                HStack {
                    Spacer()
                    Toggle("Показать скрытые", isOn: $showHidden).toggleStyle(.checkbox)
                }
            } header: {
                Text("Облик")
            } footer: {
                Text("Персонажа всегда зовут Mely, а голос откликается на «Привет, Мэли». Ненужные облики можно скрыть правой кнопкой.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(alignment: .center, spacing: 16) {
                    MelyCharacter(pose: preview)
                        .frame(width: 96, height: 96)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(look.title).font(.headline)
                        Picker("Поза", selection: $preview) {
                            ForEach(CharacterPose.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .frame(maxWidth: 240)
                    }
                }
                if look.customizations.isEmpty {
                    Text("Этот персонаж не настраивается").foregroundStyle(.secondary)
                } else {
                    ForEach(look.customizations) { option in
                        CustomizationRow(option: option, value: settings.values(for: look)[option.id] ?? option.defaultValue) {
                            settings.set(option.id, to: $0, for: look.id)
                        }
                    }
                    Button("Сбросить") { settings.reset(look.id) }
                }
            } header: {
                Text("Внешний вид")
            }

            if look.hasWardrobe {
                wardrobe(look)
            }
        }
        .formStyle(.grouped)
        .environment(\.characterAppearance, settings.appearance())
    }

    // MARK: Gallery

    private var gallery: some View {
        let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(settings.visibleLooks(showHidden: showHidden)) { look in
                LookCard(look: look, appearance: CharacterAppearance(lookId: look.id, values: settings.values(for: look),
                                                                     outfit: look.hasWardrobe ? settings.worn(for: look.id) : [:]),
                         isSelected: look.id == settings.look.id, isHidden: settings.isHidden(look.id))
                    .onTapGesture { settings.select(look.id) }
                    .contextMenu {
                        if settings.isHidden(look.id) {
                            Button("Показать") { settings.setHidden(look.id, false) }
                        } else if look.id != settings.look.id {
                            Button("Скрыть") { settings.setHidden(look.id, true) }
                        }
                    }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Wardrobe

    @ViewBuilder private func wardrobe(_ look: CharacterLook) -> some View {
        let worn = settings.worn(for: look.id)
        Section {
            HStack {
                Text("Наборы")
                Spacer()
                ForEach(OutfitSet.allCases) { set in
                    Button(set.title) { settings.wear(set, for: look.id) }
                }
                Button("Снять всё") { settings.wear(nil as OutfitSet?, for: look.id) }
            }
            ForEach(AccessorySlot.allCases, id: \.self) { slot in
                Picker(slot.title, selection: Binding(get: { worn[slot] }, set: { settings.wear($0, in: slot, for: look.id) })) {
                    Text("Ничего").tag(Accessory?.none)
                    ForEach(Accessory.items(in: slot)) { Text($0.title).tag(Accessory?.some($0)) }
                }
            }
            Toggle("Наряжать по сезону", isOn: Binding(get: { settings.dressesBySeason }, set: { settings.dressesBySeason = $0 }))
        } header: {
            Text("Гардероб")
        } footer: {
            Text("С 25 октября по 1 ноября — «Хэллоуин», с 20 декабря по 10 января — «Новый год». Если в сезон нарядить самому, сезон твой выбор не меняет. Наряд у каждого облика свой.")
                .foregroundStyle(.secondary)
        }
    }
}

/// One look in the gallery: animated, with its name.
private struct LookCard: View {
    let look: CharacterLook
    let appearance: CharacterAppearance
    let isSelected: Bool
    let isHidden: Bool

    var body: some View {
        VStack(spacing: 4) {
            MelyCharacter(pose: .idle, look: .wander)
                .environment(\.characterAppearance, appearance)
                .frame(width: 56, height: 56)
                .padding(8)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
            Text(look.title).font(.caption).lineLimit(1)
        }
        .padding(6)
        .opacity(isHidden ? 0.45 : 1)
        .background(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(look.title + (isSelected ? ", выбран" : ""))
        .accessibilityAddTraits(.isButton)
    }
}

/// A control for one customization option.
private struct CustomizationRow: View {
    let option: CustomizationOption
    let value: CustomizationValue
    let set: (CustomizationValue) -> Void

    var body: some View {
        switch option.kind {
        case .color(let palette):
            HStack {
                Text(option.title)
                Spacer()
                ForEach(palette, id: \.self) { hex in
                    Circle()
                        .fill(Color(cgColor: .hex(hex)))
                        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: value.color == hex ? 2.5 : 0).padding(-3))
                        .frame(width: 20, height: 20)
                        .onTapGesture { set(.color(hex)) }
                        .accessibilityLabel("\(option.title) \(hex)")
                        .accessibilityAddTraits(.isButton)
                }
            }
        case .toggle:
            Toggle(option.title, isOn: Binding(get: { value.bool ?? true }, set: { set(.bool($0)) }))
        case .choice(let choices):
            Picker(option.title, selection: Binding(get: { value.choice ?? choices.first?.id ?? "" }, set: { set(.choice($0)) })) {
                ForEach(choices) { Text($0.title).tag($0.id) }
            }
        case .number(let range):
            HStack {
                Text(option.title)
                Slider(value: Binding(get: { value.number ?? range.lowerBound }, set: { set(.number($0)) }), in: range)
            }
        }
    }
}
