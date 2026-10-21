import SwiftUI
import MelyCore

/// Settings → Integrations: a switch and a status per integration.
public struct IntegrationsSettingsView: View {
    let registry: IntegrationRegistry
    /// Opens the System Settings pane for a permission.
    let openPermission: (SystemPermission) -> Void

    public init(registry: IntegrationRegistry, openPermission: @escaping (SystemPermission) -> Void) {
        self.registry = registry
        self.openPermission = openPermission
    }

    public var body: some View {
        Form {
            Section {
                ForEach(registry.visible, id: \.id) { integration in
                    IntegrationRow(integration: integration,
                                   isOn: registry.isEnabled(integration.id),
                                   status: registry.status(of: integration),
                                   setOn: { on in Task { await registry.setEnabled(integration.id, on) } },
                                   openPermission: openPermission)
                }
            } header: {
                Text("Интеграции")
            } footer: {
                Text("Выключенная интеграция не работает в фоне и не запрашивает разрешений.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Показывать экспериментальные интеграции",
                       isOn: Binding(get: { registry.showExperimental }, set: { registry.showExperimental = $0 }))
            }
        }
        .formStyle(.grouped)
    }
}

struct IntegrationRow: View {
    let integration: any Integration
    let isOn: Bool
    let status: IntegrationStatus
    let setOn: (Bool) -> Void
    let openPermission: (SystemPermission) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(integration.displayName).font(.body.weight(.semibold))
                    if integration.isExperimental {
                        Text("эксперимент")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if !integration.summary.isEmpty {
                    Text(integration.summary).font(.callout).foregroundStyle(.secondary)
                }
                if isOn {
                    statusLabel
                    if !integration.actions.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(integration.actions) { action in
                                Button(action.title, role: action.isDestructive ? .destructive : nil) { action.perform() }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(get: { isOn }, set: setOn))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(integration.displayName)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var statusLabel: some View {
        switch status {
        case .off:
            EmptyView()
        case .running:
            Label("Работает", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.green)
        case .needsSetup(let message):
            Label(message, systemImage: "wrench.and.screwdriver.fill")
                .font(.callout).foregroundStyle(.orange)
        case .needsPermission(let permission):
            HStack(spacing: 8) {
                Label("Нужен доступ: \(permission.title)", systemImage: "lock.fill")
                    .font(.callout).foregroundStyle(.orange)
                Button("Открыть настройки") { openPermission(permission) }
                    .controlSize(.small)
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.red)
        }
    }
}
