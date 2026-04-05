import AppKit
import SwiftData
import os.log

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.toku345.Yank.clipboardMonitor", qos: .userInteractive)
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "ClipboardMonitor")

    /// Thread-safe storage for self-paste suppression.
    /// Set by PasteEngine before/after writing; changeCount values up to this are ignored.
    let skipLock = OSAllocatedUnfairLock(initialState: 0)

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1))

        let pasteboard = self.pasteboard
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let current = pasteboard.changeCount
            guard current != self.lastChangeCount else { return }
            self.lastChangeCount = current

            // Skip changeCount increments caused by PasteEngine writes
            let skipValue = self.skipLock.withLock { $0 }
            if current <= skipValue {
                return
            }

            Task { @MainActor [weak self] in
                self?.captureClipboard()
            }
        }
        timer.resume()
        self.timer = timer
        logger.info("Started clipboard monitoring")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        logger.info("Stopped clipboard monitoring")
    }

    private var lastCapturedString: String?

    private func captureClipboard() {
        guard let types = pasteboard.types, !types.isEmpty else { return }

        let availableTypes = types.map(\.rawValue)
        let primaryType = availableTypes[0]

        let stringValue = pasteboard.string(forType: .string)

        // Deduplicate consecutive captures of the same text
        if let text = stringValue, text == lastCapturedString {
            return
        }
        lastCapturedString = stringValue
        let rtfData = pasteboard.data(forType: .rtf)
        let rtfdData = pasteboard.data(forType: .rtfd)
        let pdfData = pasteboard.data(forType: .pdf)
        let tiffData = pasteboard.data(forType: .tiff)

        let fileURLs: [String]? = if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            urls.compactMap(\.absoluteString)
        } else {
            nil
        }

        let urlStrings: [String]? = pasteboard.string(forType: .URL).map { [$0] }

        let title = Self.deriveTitle(
            stringValue: stringValue,
            primaryType: primaryType,
            fileURLs: fileURLs
        )

        let item = ClipItem(
            title: title,
            primaryType: primaryType,
            availableTypes: availableTypes,
            stringValue: stringValue,
            rtfData: rtfData,
            rtfdData: rtfdData,
            pdfData: pdfData,
            tiffData: tiffData,
            fileURLs: fileURLs,
            urlStrings: urlStrings
        )
        modelContext.insert(item)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save ClipItem: \(error.localizedDescription, privacy: .public)")
        }

        logger.debug("Captured clip: \(title, privacy: .public) (\(primaryType, privacy: .public))")
    }

    private static func deriveTitle(stringValue: String?, primaryType: String, fileURLs: [String]?) -> String {
        if let text = stringValue, !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(50))
        }
        if let urls = fileURLs, let first = urls.first {
            return "[File: \(URL(string: first)?.lastPathComponent ?? first)]"
        }
        if primaryType.contains("tiff") || primaryType.contains("png") {
            return "[Image]"
        }
        if primaryType.contains("pdf") {
            return "[PDF]"
        }
        if primaryType.contains("rtf") {
            return "[RTF]"
        }
        return "[Clipboard Data]"
    }
}
