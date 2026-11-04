import Carbon.HIToolbox
import os

/// A keyboard shortcut that works from any app. Carbon's hot keys need no permission, and the keystroke goes to this
/// app alone, so the frontmost app doesn't also act on it. Kept for the life of the app, so it's never unregistered.
@MainActor
final class HotKey {
    private static let logger = Logger(subsystem: "com.austindick.littledia", category: "app")
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: a `kVK_…` virtual key code.
    ///   - modifiers: Carbon modifier flags (`cmdKey | shiftKey …`).
    ///   - name: for the log, if another app already has the shortcut.
    init(keyCode: Int, modifiers: Int, name: String, action: @escaping () -> Void) {
        self.action = action
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Hot-key events arrive on the main thread.
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: OSType(0x4C_44_49_41), id: 1)   // "LDIA"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            Self.logger.notice("couldn't register \(name, privacy: .public) (OSStatus \(status)); another app may have it")
        }
    }
}
