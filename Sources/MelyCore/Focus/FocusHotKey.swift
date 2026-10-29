import Foundation

/// The focus shortcut as Carbon stores it (virtual key code, modifier bits), and how it reads.
public struct FocusHotKey: Equatable, Sendable {
    public let code: Int
    public let modifiers: Int

    public init(code: Int, modifiers: Int) {
        self.code = code
        self.modifiers = modifiers
    }

    // Carbon's modifier bits (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public static let command = 0x0100, shift = 0x0200, option = 0x0800, control = 0x1000

    /// Mely's other shortcuts: ⌃⌥Space opens the chat, ⌃⌥D takes Mely to the desktop.
    public static let taken = [FocusHotKey(code: 49, modifiers: control | option), FocusHotKey(code: 2, modifiers: control | option)]

    /// «⌃⌥P», in the order macOS menus write them.
    public var label: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keys[code] ?? "#\(code)")
    }

    /// Why it cannot be the shortcut, or nil: a key alone (or with only ⇧) would fire while
    /// typing; Mely's own shortcuts are taken.
    public var problem: String? {
        if modifiers & (Self.control | Self.option | Self.command) == 0 { return "Нужен ⌃, ⌥ или ⌘" }
        if Self.taken.contains(self) { return "\(label) уже занято в Mely" }
        return nil
    }

    /// ANSI key codes (`kVK_ANSI_*`) and a few named keys.
    static let keys: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12",
    ]
}
