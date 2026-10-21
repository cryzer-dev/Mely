import SwiftUI
import MelyCore

/// How the chat reaches Claude, the API key and the model. The key goes straight to the Keychain.
public struct ChatSettingsView: View {
    let hasKey: Bool
    let claudeFound: Bool
    let save: (_ route: ChatRoute, _ key: String?, _ model: ChatModel) throws -> Void
    let removeKey: () -> Void
    let close: () -> Void
    @State private var route: ChatRoute
    @State private var key = ""
    @State private var model: ChatModel
    @State private var error: String?

    public init(route: ChatRoute, hasKey: Bool, claudeFound: Bool, model: ChatModel,
                save: @escaping (ChatRoute, String?, ChatModel) throws -> Void,
                removeKey: @escaping () -> Void, close: @escaping () -> Void) {
        self.hasKey = hasKey
        self.claudeFound = claudeFound
        self.save = save
        self.removeKey = removeKey
        self.close = close
        _route = State(initialValue: route)
        _model = State(initialValue: model)
    }

    private var keyMissing: Bool {
        route == .apiKey && !hasKey && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Чат с Claude").font(.title3.weight(.semibold))
            Picker("Через что отвечать", selection: $route) {
                ForEach(ChatRoute.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            switch route {
            case .subscription:
                Text(claudeFound
                     ? "Ответы идут через Claude Code, в котором вы вошли в аккаунт: ключ не нужен, расходуется лимит вашего плана. Claude отвечает без инструментов и не трогает файлы."
                     : "Claude Code не найден на этом Mac. Установите его (claude.com/claude-code) и войдите командой /login, или выберите ключ API.")
                    .font(.callout).foregroundStyle(claudeFound ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            case .apiKey:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Оплачивается по использованию. Ключ хранится только в связке ключей этого Mac.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    SecureField(hasKey ? "Ключ сохранён — введите новый, чтобы заменить" : "sk-ant-…", text: $key)
                        .textFieldStyle(.roundedBorder)
                    Link("Получить ключ в Claude Console", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.caption)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Модель").font(.headline)
                Picker("Модель", selection: $model) {
                    ForEach(ChatModel.allCases) { m in
                        Text("\(m.title) — \(m.note)").tag(m)
                    }
                }
                .labelsHidden()
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
            }
            HStack {
                if hasKey && route == .apiKey {
                    Button("Удалить ключ", role: .destructive) { removeKey(); close() }
                }
                Spacer()
                Button("Отмена", action: close).keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    do {
                        try save(route, trimmed.isEmpty ? nil : trimmed, model)
                        close()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keyMissing)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
