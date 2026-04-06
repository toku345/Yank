import AppKit
import SwiftData
import os.log

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "ClipboardMonitor")

    /// Thread-safe storage for self-paste suppression.
    /// PasteEngine sets this to Int.max before writing and updates it to the actual
    /// changeCount after writing. The monitor ignores any changeCount <= this value.
    let skipLock = OSAllocatedUnfairLock(initialState: 0)

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollClipboard() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        logger.info("Started clipboard monitoring")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        logger.info("Stopped clipboard monitoring")
    }

    private func pollClipboard() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        let skipValue = skipLock.withLock { $0 }
        if current <= skipValue { return }

        captureClipboard()
    }

    private var lastCapturedString: String?
    private var lastCapturedType: String?

    private func captureClipboard() {
        guard let types = pasteboard.types, !types.isEmpty else { return }

        let availableTypes = types.map(\.rawValue)
        let primaryType = availableTypes[0]

        let stringValue = pasteboard.string(forType: .string)

        // Deduplicate consecutive captures of the same content
        if let text = stringValue, text == lastCapturedString, primaryType == lastCapturedType {
            return
        }
        lastCapturedString = stringValue
        lastCapturedType = primaryType

        let rtfData = pasteboard.data(forType: .rtf)
        let rtfdData = pasteboard.data(forType: .rtfd)
        let pdfData = pasteboard.data(forType: .pdf)
        let pngData = pasteboard.data(forType: .png)
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
            pngData: pngData,
            tiffData: tiffData,
            fileURLs: fileURLs,
            urlStrings: urlStrings
        )
        modelContext.insert(item)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(item)
            logger.error("Failed to save ClipItem: \(error.localizedDescription, privacy: .public)")
        }

        logger.debug("Captured clip: \(title, privacy: .private) (\(primaryType, privacy: .public))")
    }

    static func deriveTitle(stringValue: String?, primaryType: String, fileURLs: [String]?) -> String {
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
