import SwiftUI
import MelyCore

/// Shows a pending ~/.claude/settings.json change and asks for the OK before writing.
public struct SettingsChangeView: View {
    let change: PendingSettingsChange
    let error: String?
    let onApply: () -> Void
    let onCancel: () -> Void

    public init(change: PendingSettingsChange, error: String?, onApply: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.change = change
        self.error = error
        self.onApply = onApply
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(change.title).font(.title3.weight(.semibold))
            Text(change.note ?? "Mely изменит ~/.claude/settings.json. Перед записью будет сделана резервная копия рядом с файлом, чужие hooks останутся на месте.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(change.diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                        Text(String(line))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(background(for: line))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .frame(minHeight: 220)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Отмена", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button("Применить", action: onApply).keyboardShortcut(.defaultAction).disabled(change.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }

    private func color(for line: Substring) -> Color {
        line.hasPrefix("+ ") ? Color(red: 0.1, green: 0.5, blue: 0.2)
            : line.hasPrefix("- ") ? Color(red: 0.7, green: 0.15, blue: 0.15) : .primary
    }

    private func background(for line: Substring) -> Color {
        line.hasPrefix("+ ") ? .green.opacity(0.10) : line.hasPrefix("- ") ? .red.opacity(0.10) : .clear
    }
}
