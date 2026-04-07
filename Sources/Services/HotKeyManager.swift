import Carbon
import os.log

enum HotKeyError: Error {
    case installFailed(status: OSStatus)
    case registrationFailed(status: OSStatus)
}

@MainActor
final class HotKeyManager {
    private var registration: (hotKey: EventHotKeyRef, handler: EventHandlerRef)?
    /// Raw pointer from passRetained(self), used as Carbon callback userData.
    /// Stored to ensure unregister() releases the exact same reference.
    private var retainedSelfPtr: UnsafeMutableRawPointer?
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

        // passRetained adds +1 to RC. Balanced by fromOpaque(...).release() in unregister().
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

        retainedSelfPtr = selfPtr
        registration = (hotKey: hotKey!, handler: handler!)
        logger.info("Registered global hotkey Cmd+Shift+V")
    }

    func unregister() {
        guard let reg = registration else { return }
        let unregStatus = UnregisterEventHotKey(reg.hotKey)
        if unregStatus != noErr {
            logger.warning("UnregisterEventHotKey failed: \(unregStatus)")
        }
        let removeStatus = RemoveEventHandler(reg.handler)
        if removeStatus != noErr {
            logger.warning("RemoveEventHandler failed: \(removeStatus)")
        }
        // Release the +1 retain from passRetained in register()
        Unmanaged<HotKeyManager>.fromOpaque(retainedSelfPtr!).release()
        retainedSelfPtr = nil
        registration = nil
        logger.info("Unregistered global hotkey")
    }

    // passRetained in register() prevents deallocation while registered.
    // deinit only fires after unregister() has released the retain and set registration = nil.
    deinit {}
}

// Carbon event handlers run on the main thread (application event target)
private func hotKeyCallback(
    _: EventHandlerCallRef?,
    _: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
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
