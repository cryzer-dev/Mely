import Foundation

/// "Открыть в Claude": a new chat in the Claude desktop app with the conversation already
/// in the field, through the link the app's own "Ask Claude" service uses.
public enum ClaudeDesktopHandoff {
    public static let bundleId = "com.anthropic.claudefordesktop"
    /// The service reads at most 16 KiB of text; keep the end, where the latest answers are.
    static let maxBytes = 16_000

    /// The conversation as text for the new chat.
    @MainActor
    public static func prompt(for conversation: ChatConversation) -> String {
        var parts = ["Продолжим разговор из Mely:"]
        if let context = conversation.context { parts.append("(открыт из \(context.label))") }
        for message in conversation.messages where !message.text.isEmpty {
            parts.append((message.role == .user ? "Я: " : "Claude: ") + message.text)
        }
        return parts.joined(separator: "\n\n")
    }

    public static func url(for text: String) -> URL? {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "claude.ai"
        components.path = "/new"
        components.queryItems = [URLQueryItem(name: "q", value: tail(text)),
                                 URLQueryItem(name: "surface", value: "chat"),
                                 URLQueryItem(name: "source", value: "services")]
        return components.url
    }

    /// The last `maxBytes` of UTF-8, cut on a character boundary, marked when cut.
    static func tail(_ text: String) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var cut = Substring(text)
        while cut.utf8.count > maxBytes - 4 { cut = cut.dropFirst() }
        return "…\n" + cut
    }
}
