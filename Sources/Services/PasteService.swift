import AppKit
import Carbon.HIToolbox
import os.log

enum PasteService {
    private static let logger = Logger(subsystem: "com.toku345.Yank", category: "PasteService")

    @discardableResult
    static func writeToPasteboard(item: ClipItem, pasteboard: NSPasteboard = .general) -> Bool {
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

        guard writePreservingOnFailure(objects, to: pasteboard) else {
            logger.error("writeObjects failed; restored snapshot for: \(item.title, privacy: .private)")
            return false
        }
        logger.debug("Wrote to pasteboard: \(item.title, privacy: .private)")
        return true
    }

    @discardableResult
    static func writePlainTextToPasteboard(item: ClipItem, pasteboard: NSPasteboard = .general) -> Bool {
        // Derive text BEFORE touching the pasteboard so a validation failure
        // leaves the user's existing clipboard intact.
        guard let textValue = derivePlainText(from: item) else {
            logger.warning("No text representation for plain-text paste: \(item.title, privacy: .private)")
            return false
        }

        let pbItem = NSPasteboardItem()
        pbItem.setString(textValue, forType: .string)
        // Self-paste suppression marker (ADR 0002)
        pbItem.setString("", forType: .fromYank)

        guard writePreservingOnFailure([pbItem], to: pasteboard) else {
            logger.error("writePlainTextToPasteboard failed; restored snapshot for: \(item.title, privacy: .private)")
            return false
        }
        logger.debug("Wrote plain text to pasteboard: \(item.title, privacy: .private)")
        return true
    }

    /// Snapshots the pasteboard, clears it, writes `objects`, and restores
    /// the snapshot on failure. Protects the user's clipboard against the
    /// rare case where writeObjects returns false after clearContents.
    private static func writePreservingOnFailure(
        _ objects: [NSPasteboardWriting],
        to pasteboard: NSPasteboard
    ) -> Bool {
        let snapshot = snapshotPasteboardItems(pasteboard)
        pasteboard.clearContents()
        if pasteboard.writeObjects(objects) { return true }
        pasteboard.clearContents()
        if !snapshot.isEmpty, !pasteboard.writeObjects(snapshot) {
            logger.warning("Failed to restore pasteboard snapshot; user clipboard may be empty")
        }
        return false
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
            // Let AppKit infer the charset: forcing .characterEncoding would
            // override <meta charset> and break non-UTF-8 HTML.
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: docType]
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
