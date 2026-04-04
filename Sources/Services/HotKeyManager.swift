import Carbon
import os.log

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "HotKeyManager")
    var onToggle: (() -> Void)?

    func register() {
        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("YnkH"),
            id: 1
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyCallback,
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            logger.info("Registered global hotkey Cmd+Shift+V")
        } else {
            logger.error("Failed to register hotkey: \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
        logger.info("Unregistered global hotkey")
    }

    deinit {
        unregister()
    }
}

private func hotKeyCallback(
    _: EventHandlerCallRef?,
    _: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        manager.onToggle?()
    }
    return noErr
}

private func fourCharCode(_ string: String) -> OSType {
    var result: UInt32 = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | UInt32(char)
    }
    return OSType(result)
}
