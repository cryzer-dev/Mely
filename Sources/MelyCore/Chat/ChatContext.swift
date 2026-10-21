import Foundation

/// The window the user was in when they opened the chat: the first question carries it,
/// so "переведи это" or "что на этой странице?" make sense.
public struct ChatContext: Equatable, Sendable {
    public let appName: String
    public let windowTitle: String
    /// The browser's page, when the app is a browser that told us.
    public let url: String?

    public init(appName: String, windowTitle: String, url: String?) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
    }

    /// The chip: "Safari · habr.com", or the app name.
    public var label: String {
        if let url, let host = URL(string: url)?.host { return "\(appName) · \(host)" }
        return appName
    }

    /// The text block added before the first question.
    var prompt: String {
        var parts = ["приложение «\(appName)»"]
        if !windowTitle.isEmpty { parts.append("окно «\(windowTitle)»") }
        if let url { parts.append("адрес \(url)") }
        return "Контекст: пользователь открыл чат из \(parts.joined(separator: ", ")). Учитывай это, если вопрос о нём."
    }
}
