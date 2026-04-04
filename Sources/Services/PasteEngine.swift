import AppKit
import Carbon.HIToolbox
import os.log

enum PasteEngine {
    private static let logger = Logger(subsystem: "com.toku345.Yank", category: "PasteEngine")

    static func paste(item: ClipItem, monitor: ClipboardMonitor) {
        writeToPasteboard(item: item, monitor: monitor)

        // 前面アプリがフォーカスを取り戻す時間を確保してからペースト
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            simulateCmdV()
        }
    }

    static func writeToPasteboard(item: ClipItem, monitor: ClipboardMonitor) {
        monitor.ignoringNextChange = true

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var types: [NSPasteboard.PasteboardType] = []
        if item.stringValue != nil { types.append(.string) }
        if item.rtfData != nil { types.append(.rtf) }
        if item.rtfdData != nil { types.append(.rtfd) }
        if item.pdfData != nil { types.append(.pdf) }
        if item.tiffData != nil { types.append(.tiff) }
        if item.urlStrings != nil { types.append(.URL) }
        if item.fileURLs != nil { types.append(.fileURL) }

        pasteboard.declareTypes(types, owner: nil)

        if let s = item.stringValue {
            pasteboard.setString(s, forType: .string)
        }
        if let d = item.rtfData {
            pasteboard.setData(d, forType: .rtf)
        }
        if let d = item.rtfdData {
            pasteboard.setData(d, forType: .rtfd)
        }
        if let d = item.pdfData {
            pasteboard.setData(d, forType: .pdf)
        }
        if let d = item.tiffData {
            pasteboard.setData(d, forType: .tiff)
        }
        if let urls = item.urlStrings, let first = urls.first {
            pasteboard.setString(first, forType: .URL)
        }
        if let urls = item.fileURLs, let first = urls.first {
            pasteboard.setString(first, forType: .fileURL)
        }

        logger.debug("Wrote to pasteboard: \(item.title, privacy: .public)")
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            logger.error("Failed to create CGEvent for Cmd+V")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        logger.debug("Simulated Cmd+V")
    }
}
