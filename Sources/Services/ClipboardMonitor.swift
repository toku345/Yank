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

    private var lastCapturedFingerprint: Int?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
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

    private struct PasteboardSnapshot {
        let availableTypes: [String]
        let primaryType: String
        let stringValue: String?
        let rtfData, rtfdData, htmlData, pdfData, imageData: Data?
        let fileURLs: [String]?

        var fingerprint: Int {
            var hasher = Hasher()
            hasher.combine(stringValue)
            hasher.combine(primaryType)
            hasher.combine(rtfData)
            hasher.combine(rtfdData)
            hasher.combine(htmlData)
            hasher.combine(pdfData)
            hasher.combine(imageData)
            hasher.combine(fileURLs)
            return hasher.finalize()
        }
    }

    /// Reads pasteboard data. Returns nil if no restorable payload exists.
    private func readPasteboard() -> PasteboardSnapshot? {
        guard let types = pasteboard.types, !types.isEmpty else { return nil }

        let availableTypes = types.map(\.rawValue)
        let stringValue = pasteboard.string(forType: .string)
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
        let hasFileURLs = fileURLs != nil && !fileURLs!.isEmpty

        // Skip entries that PasteService cannot restore
        guard stringValue != nil || rtfData != nil || rtfdData != nil
                || htmlData != nil || pdfData != nil || imageData != nil || hasFileURLs else {
            return nil
        }

        return PasteboardSnapshot(
            availableTypes: availableTypes, primaryType: availableTypes[0],
            stringValue: stringValue, rtfData: rtfData, rtfdData: rtfdData,
            htmlData: htmlData, pdfData: pdfData, imageData: imageData, fileURLs: fileURLs
        )
    }

    private func captureClipboard() {
        guard let snapshot = readPasteboard() else {
            logger.debug("Skipping clip with no restorable payload")
            return
        }

        // Deduplicate consecutive captures using a fingerprint of all content
        let fingerprint = snapshot.fingerprint
        if fingerprint == lastCapturedFingerprint { return }

        let title = Self.deriveTitle(
            stringValue: snapshot.stringValue,
            primaryType: snapshot.primaryType,
            fileURLs: snapshot.fileURLs
        )

        let item = ClipItem(
            title: title,
            primaryType: snapshot.primaryType,
            availableTypes: snapshot.availableTypes,
            stringValue: snapshot.stringValue,
            rtfData: snapshot.rtfData,
            rtfdData: snapshot.rtfdData,
            htmlData: snapshot.htmlData,
            pdfData: snapshot.pdfData,
            imageData: snapshot.imageData,
            fileURLs: snapshot.fileURLs
        )
        modelContext.insert(item)
        do {
            try modelContext.save()
            lastCapturedFingerprint = fingerprint
        } catch {
            modelContext.delete(item)
            logger.error("Failed to save ClipItem: \(error.localizedDescription, privacy: .public)")
        }

        logger.debug("Captured clip: \(title, privacy: .private) (\(snapshot.primaryType, privacy: .public))")
    }

    static func deriveTitle(stringValue: String?, primaryType: String, fileURLs: [String]?) -> String {
        if let text = stringValue, !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(50))
            }
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
