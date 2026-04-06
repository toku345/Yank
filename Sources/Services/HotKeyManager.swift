import Carbon
import os.log

enum HotKeyError: Error {
    case installFailed(status: OSStatus)
    case registrationFailed(status: OSStatus)
}

final class HotKeyManager {
    private var registration: (hotKey: EventHotKeyRef, handler: EventHandlerRef)?
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "HotKeyManager")
    var onToggle: (() -> Void)?

    func register() throws {
        guard registration == nil else {
            logger.warning("Hotkey already registered")
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("YnkH"),
            id: 1
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Carbon API callback requires a raw pointer to the manager instance.
        // passRetained is balanced by release in unregister().
        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        var handler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyCallback,
            1,
            &eventType,
            selfPtr,
            &handler
        )
        guard installStatus == noErr else {
            Unmanaged<HotKeyManager>.fromOpaque(selfPtr).release()
            throw HotKeyError.installFailed(status: installStatus)
        }

        var hotKey: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard regStatus == noErr else {
            RemoveEventHandler(handler!)
            Unmanaged<HotKeyManager>.fromOpaque(selfPtr).release()
            throw HotKeyError.registrationFailed(status: regStatus)
        }

        registration = (hotKey: hotKey!, handler: handler!)
        logger.info("Registered global hotkey Cmd+Shift+V")
    }

    func unregister() {
        guard let reg = registration else { return }
        UnregisterEventHotKey(reg.hotKey)
        RemoveEventHandler(reg.handler)
        Unmanaged<HotKeyManager>.passUnretained(self).release()
        registration = nil
        logger.info("Unregistered global hotkey")
    }

    deinit {
        // unregister() releases the passRetained reference, so deinit only fires
        // after unregister() is called (via applicationWillTerminate / shutdown).
        // Guard against double-release: if registration is already nil, nothing to do.
        if registration != nil {
            let reg = registration!
            UnregisterEventHotKey(reg.hotKey)
            RemoveEventHandler(reg.handler)
            registration = nil
        }
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
