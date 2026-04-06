import AppKit
import Carbon.HIToolbox
import os.log

// Self-paste suppression inspired by Maccy (MIT License, Copyright 2025 Alex Rodionov)
// https://github.com/p0deje/Maccy
extension NSPasteboard.PasteboardType {
    static let fromYank = NSPasteboard.PasteboardType("com.toku345.Yank.self-paste")
}

enum PasteService {
    private static let logger = Logger(subsystem: "com.toku345.Yank", category: "PasteService")

    /// Convenience: writes to pasteboard then simulates Cmd+V.
    /// AppCoordinator may call writeToPasteboard/simulateCmdV separately
    /// to insert a panel close between them (ADR 0003).
    static func paste(item: ClipItem) {
        writeToPasteboard(item: item)
        simulateCmdV()
    }

    static func writeToPasteboard(item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let dataEntries: [(NSPasteboard.PasteboardType, Data?)] = [
            (.rtf, item.rtfData),
            (.rtfd, item.rtfdData),
            (.html, item.htmlData),
            (.pdf, item.pdfData),
            (.tiff, item.imageData)
        ]

        var types: [NSPasteboard.PasteboardType] = []
        if item.stringValue != nil { types.append(.string) }
        for (type, data) in dataEntries where data != nil { types.append(type) }
        types.append(.fromYank)

        pasteboard.declareTypes(types, owner: nil)

        if let string = item.stringValue {
            pasteboard.setString(string, forType: .string)
        }
        for (type, data) in dataEntries {
            if let data { pasteboard.setData(data, forType: type) }
        }

        // Restore file URLs (Finder multi-file copy uses one pasteboard item per URL)
        if let fileURLPaths = item.fileURLs, !fileURLPaths.isEmpty {
            let nsurls = fileURLPaths.compactMap { URL(string: $0) }.map { $0 as NSURL }
            pasteboard.writeObjects(nsurls)
        }

        // Self-paste suppression marker
        pasteboard.setString("", forType: .fromYank)

        logger.debug("Wrote to pasteboard: \(item.title, privacy: .private)")
    }

    static func simulateCmdV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("Failed to create CGEventSource -- check Accessibility permissions")
            return
        }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            logger.error("Failed to create CGEvent for Cmd+V")
            return
        }

        // NX_NONCOALESCED (0x000008): prevent event coalescing which silently drops keystrokes
        let cmdFlag = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        keyDown.flags = cmdFlag
        keyUp.flags = cmdFlag
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        logger.debug("Simulated Cmd+V via CGEvent")
    }
}
