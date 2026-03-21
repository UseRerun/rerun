import AppKit
import Carbon
import os

private let logger = Logger(subsystem: "com.rerun", category: "HotkeyManager")

@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let toggleHandler: @MainActor () -> Void

    // Stored globally so the C callback can reach it
    fileprivate static var instance: HotkeyManager?

    init(toggleHandler: @MainActor @escaping () -> Void) {
        self.toggleHandler = toggleHandler
    }

    func start() {
        HotkeyManager.instance = self

        // Install Carbon event handler for hotkey press
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard status == noErr else {
            logger.error("Failed to install Carbon event handler: \(status)")
            return
        }

        // Register Cmd+Shift+Option+Space
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x5252_554E), // "RRUN"
            id: 1
        )
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey | optionKey)
        let keyCode: UInt32 = 49 // space

        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus == noErr {
            logger.notice("Registered global hotkey: Cmd+Shift+Option+Space")
        } else {
            logger.error("Failed to register hotkey: \(regStatus)")
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        HotkeyManager.instance = nil
    }

    fileprivate func handleHotKey() {
        logger.notice("Hotkey triggered")
        toggleHandler()
    }
}

// Carbon callback — must be a free function
private func carbonHotkeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    MainActor.assumeIsolated {
        HotkeyManager.instance?.handleHotKey()
    }
    return noErr
}
