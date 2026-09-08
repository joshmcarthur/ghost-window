import AppKit
import Carbon
import Foundation

/// Global ⌘⇧G hotkey using Carbon `RegisterEventHotKey`.
/// This works while other applications are focused and does not require a key-event tap.
final class GlobalShortcut: @unchecked Sendable {
    static let defaultKeyCode = UInt32(kVK_ANSI_G)
    static let defaultModifiers = UInt32(cmdKey | shiftKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x47574854 // 'GWHT'
    private let hotKeyNumericID: UInt32 = 1

    func register(onTrigger: @escaping () -> Void) {
        unregister()
        GlobalShortcutState.onTrigger = onTrigger
        installHandler()

        let hotKeyID = EventHotKeyID(signature: signature, id: hotKeyNumericID)
        let status = RegisterEventHotKey(
            GlobalShortcut.defaultKeyCode,
            GlobalShortcut.defaultModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            GhostLogger.log("Failed to register ⌘⇧G hotkey: \(status)")
        } else {
            GhostLogger.log("Registered global shortcut ⌘⇧G")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        GlobalShortcutState.onTrigger = nil
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            globalShortcutHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        if status != noErr {
            GhostLogger.log("Failed to install hotkey handler: \(status)")
        }
    }
}

private enum GlobalShortcutState {
    static var onTrigger: (() -> Void)?
}

private func globalShortcutHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        GlobalShortcutState.onTrigger?()
    }
    return noErr
}
