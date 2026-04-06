import AppKit
import SwiftData
import UniformTypeIdentifiers
import os.log

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "ClipboardMonitor")

    private var lastCapturedString: String?
    private var lastCapturedType: String?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            // Timer on main RunLoop guarantees main thread execution
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

        // Self-paste suppression: skip if our marker is present (ADR 0002)
        if pasteboard.types?.contains(.fromYank) == true { return }

        captureClipboard()
    }

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
        let htmlData = pasteboard.data(forType: .html)
        let pdfData = pasteboard.data(forType: .pdf)
        let imageData = pasteboard.data(forType: .tiff)

        let fileURLs: [String]? = if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            urls.compactMap(\.absoluteString)
        } else {
            nil
        }

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
            htmlData: htmlData,
            pdfData: pdfData,
            imageData: imageData,
            fileURLs: fileURLs
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
        if let uttype = UTType(primaryType) {
            if uttype.conforms(to: .image) { return "[Image]" }
            if uttype.conforms(to: .pdf) { return "[PDF]" }
            if uttype.conforms(to: .rtfd) { return "[RTFD]" }
            if uttype.conforms(to: .rtf) { return "[RTF]" }
            if uttype.conforms(to: .html) { return "[HTML]" }
        }
        return "[Clipboard Data]"
    }
}
