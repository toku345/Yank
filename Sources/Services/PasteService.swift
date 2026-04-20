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

    @discardableResult
    static func writeToPasteboard(item: ClipItem) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Use NSPasteboardItem (modern API) exclusively.
        // Apple SDK: "declareTypes should not be used with writeObjects"
        let pbItem = NSPasteboardItem()

        if let string = item.stringValue {
            pbItem.setString(string, forType: .string)
        }
        if let data = item.rtfData { pbItem.setData(data, forType: .rtf) }
        if let data = item.rtfdData { pbItem.setData(data, forType: .rtfd) }
        if let data = item.htmlData { pbItem.setData(data, forType: .html) }
        if let data = item.pdfData { pbItem.setData(data, forType: .pdf) }
        if let data = item.imageData { pbItem.setData(data, forType: .tiff) }

        // Self-paste suppression marker (ADR 0002)
        pbItem.setString("", forType: .fromYank)

        var objects: [NSPasteboardWriting] = [pbItem]

        // Finder multi-file copy uses one pasteboard item per URL
        if let fileURLPaths = item.fileURLs, !fileURLPaths.isEmpty {
            let nsurls = fileURLPaths.compactMap { URL(string: $0) }.map { $0 as NSURL }
            objects.append(contentsOf: nsurls)
        }

        let success = pasteboard.writeObjects(objects)
        if !success {
            logger.error("writeObjects failed for: \(item.title, privacy: .private)")
        } else {
            logger.debug("Wrote to pasteboard: \(item.title, privacy: .private)")
        }
        return success
    }

    @discardableResult
    static func writePlainTextToPasteboard(item: ClipItem) -> Bool {
        // Derive text BEFORE touching the pasteboard so a validation failure
        // leaves the user's existing clipboard intact.
        guard let textValue = derivePlainText(from: item) else {
            logger.warning("No text representation for plain-text paste: \(item.title, privacy: .private)")
            return false
        }

        let pasteboard = NSPasteboard.general
        // Snapshot for restore: writeObjects can fail after clearContents
        // (rare) and without this the user's previous clipboard is lost.
        let snapshot = snapshotPasteboardItems(pasteboard)
        pasteboard.clearContents()

        let pbItem = NSPasteboardItem()
        pbItem.setString(textValue, forType: .string)
        // Self-paste suppression marker (ADR 0002)
        pbItem.setString("", forType: .fromYank)

        guard pasteboard.writeObjects([pbItem]) else {
            logger.error("writePlainTextToPasteboard failed; restoring snapshot for: \(item.title, privacy: .private)")
            pasteboard.clearContents()
            if !snapshot.isEmpty {
                _ = pasteboard.writeObjects(snapshot)
            }
            return false
        }
        logger.debug("Wrote plain text to pasteboard: \(item.title, privacy: .private)")
        return true
    }

    private static func derivePlainText(from item: ClipItem) -> String? {
        if let string = item.stringValue { return string }
        if let urls = item.fileURLs, !urls.isEmpty {
            let joined = urls.compactMap { URL(string: $0)?.path }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        // Fallback for rich-text-only clips (HTML/RTF/RTFD without a .string twin)
        return extractRichText(from: item)
    }

    private static func extractRichText(from item: ClipItem) -> String? {
        let candidates: [(Data?, NSAttributedString.DocumentType)] = [
            (item.htmlData, .html),
            (item.rtfData, .rtf),
            (item.rtfdData, .rtfd)
        ]
        for (data, docType) in candidates {
            guard let data else { continue }
            var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: docType]
            if docType == .html {
                options[.characterEncoding] = String.Encoding.utf8.rawValue
            }
            guard let attr = try? NSAttributedString(data: data, options: options, documentAttributes: nil),
                  !attr.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            return attr.string
        }
        return nil
    }

    private static func snapshotPasteboardItems(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).compactMap { oldItem in
            let copy = NSPasteboardItem()
            var copied = false
            for type in oldItem.types {
                if let data = oldItem.data(forType: type) {
                    copy.setData(data, forType: type)
                    copied = true
                }
            }
            return copied ? copy : nil
        }
    }

    /// Returns false if CGEvent creation fails (typically Accessibility permission missing).
    @discardableResult
    static func simulateCmdV() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("Failed to create CGEventSource -- check Accessibility permissions")
            return false
        }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            logger.error("Failed to create CGEvent for Cmd+V")
            return false
        }

        // NX_NONCOALESCED (0x000008): prevent event coalescing which silently drops keystrokes
        let cmdFlag = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        keyDown.flags = cmdFlag
        keyUp.flags = cmdFlag
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)

        logger.debug("Simulated Cmd+V via CGEvent")
        return true
    }
}
