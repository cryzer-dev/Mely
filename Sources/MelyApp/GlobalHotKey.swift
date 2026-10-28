import Carbon.HIToolbox
import AppKit

/// A system-wide shortcut through Carbon's RegisterEventHotKey: works with any app in
/// front and needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    let keyCode: Int
    let modifiers: Int
    /// Each shortcut has its own id: every handler sees every press and keeps only its own.
    private let number: UInt32
    private static var count: UInt32 = 0

    /// ⌃⌥Space by default.
    init(keyCode: Int = kVK_Space, modifiers: Int = controlKey | optionKey, action: @escaping () -> Void) {
        self.action = action
        self.keyCode = keyCode
        self.modifiers = modifiers
        Self.count += 1
        number = Self.count
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            guard pressed.id == hotKey.number else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, me, &handler)
        let id = EventHotKeyID(signature: OSType(0x4D454C59), id: number)  // "MELY"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }

    isolated deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
