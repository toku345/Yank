import AppKit
import Carbon.HIToolbox
import os.log

enum PasteEngine {
    private static let logger = Logger(subsystem: "com.toku345.Yank", category: "PasteEngine")

    static func paste(item: ClipItem, monitor: ClipboardMonitor) {
        writeToPasteboard(item: item, monitor: monitor)

        // Allow the frontmost app to regain focus before simulating Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulateCmdV()
        }
    }

    static func writeToPasteboard(item: ClipItem, monitor: ClipboardMonitor) {
        // Block monitor from detecting changeCount changes during our write
        monitor.skipLock.withLock { $0 = Int.max }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let dataEntries: [(NSPasteboard.PasteboardType, Data?)] = [
            (.rtf, item.rtfData),
            (.rtfd, item.rtfdData),
            (.pdf, item.pdfData),
            (.tiff, item.tiffData)
        ]

        var types: [NSPasteboard.PasteboardType] = []
        if item.stringValue != nil { types.append(.string) }
        for (type, data) in dataEntries where data != nil { types.append(type) }
        if item.urlStrings != nil { types.append(.URL) }
        if item.fileURLs != nil { types.append(.fileURL) }

        pasteboard.declareTypes(types, owner: nil)

        if let string = item.stringValue {
            pasteboard.setString(string, forType: .string)
        }
        for (type, data) in dataEntries {
            if let data { pasteboard.setData(data, forType: type) }
        }
        if let urls = item.urlStrings, let first = urls.first {
            pasteboard.setString(first, forType: .URL)
        }
        if let urls = item.fileURLs, let first = urls.first {
            pasteboard.setString(first, forType: .fileURL)
        }

        // Update to actual changeCount so monitor skips only our writes
        monitor.skipLock.withLock { $0 = pasteboard.changeCount }

        logger.debug("Wrote to pasteboard: \(item.title, privacy: .public)")
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            logger.error("Failed to create CGEvent for Cmd+V")
            return
        }

        // 0x000008 = NX_NONCOALESCED: prevent event coalescing which silently drops keystrokes
        let cmdFlag = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        keyDown.flags = cmdFlag
        keyUp.flags = cmdFlag
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        logger.debug("Simulated Cmd+V via CGEvent")
    }
}
