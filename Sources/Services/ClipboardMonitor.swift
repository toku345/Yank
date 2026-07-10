import AppKit
import SwiftData
import UniformTypeIdentifiers
import os.log

private enum PasteboardReadResult {
    case snapshot(PasteboardSnapshot)
    case skipped(PasteboardSkipReason)
}

private enum PasteboardSkipReason {
    case noTypes
    case captureSkipMarker(NSPasteboard.PasteboardType)
}

@MainActor
final class ClipboardMonitor {
    typealias PersistSnapshot = @Sendable (PasteboardSnapshot) async -> ClipboardPersistenceResult

    // Exposed (internal) so tests can assert the injected default is `.general`.
    let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let persistSnapshot: PersistSnapshot
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "ClipboardMonitor")

    private var isCaptureInFlight = false
    private var isMonitoring = false

    init(
        modelContainer: ModelContainer,
        pasteboard: NSPasteboard = .general,
        historyLimit: Int = ClipboardHistoryPolicy.defaultLimit,
        persistSnapshot: PersistSnapshot? = nil
    ) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        if let persistSnapshot {
            self.persistSnapshot = persistSnapshot
        } else {
            let writer = ClipboardHistoryWriter(
                modelContainer: modelContainer,
                historyLimit: historyLimit
            )
            self.persistSnapshot = { snapshot in
                await writer.persist(snapshot)
            }
        }
    }

    func start() {
        timer?.invalidate()
        isMonitoring = true
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            // Timer on main RunLoop guarantees main thread execution
            MainActor.assumeIsolated { self?.pollClipboard() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        logger.info("Started clipboard monitoring")
    }

    func stop() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        logger.info("Stopped clipboard monitoring")
    }

    // Internal to support deterministic one-in-flight tests without waiting for
    // the timer. Production polling still comes exclusively from start().
    func pollClipboard() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        guard !isCaptureInFlight else { return }
        lastChangeCount = current

        // Self-paste suppression: skip if our marker is present (ADR 0002)
        if pasteboard.types?.contains(.fromYank) == true { return }

        captureClipboard(createdAt: Date())
    }

    /// Reads pasteboard data and skips external capture markers. Payload
    /// normalization and restorable-payload validation happen on the writer.
    private func readPasteboard(createdAt: Date) -> PasteboardReadResult {
        guard let types = pasteboard.types, !types.isEmpty else { return .skipped(.noTypes) }
        if let marker = types.first(where: { NSPasteboard.PasteboardType.externalCaptureSkipMarkers.contains($0) }) {
            return .skipped(.captureSkipMarker(marker))
        }

        let availableTypes = types.map(\.rawValue)
        let fileURLs: [String]? = if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            urls.compactMap(\.absoluteString)
        } else {
            nil
        }

        return .snapshot(PasteboardSnapshot(
            availableTypes: availableTypes,
            primaryType: availableTypes[0],
            stringValue: pasteboard.string(forType: .string),
            rtfData: pasteboard.data(forType: .rtf),
            rtfdData: pasteboard.data(forType: .rtfd),
            htmlData: pasteboard.data(forType: .html),
            pdfData: pasteboard.data(forType: .pdf),
            imageData: pasteboard.data(forType: .tiff),
            fileURLs: fileURLs,
            createdAt: createdAt
        ))
    }

    private func captureClipboard(createdAt: Date) {
        let snapshot: PasteboardSnapshot
        switch readPasteboard(createdAt: createdAt) {
        case let .snapshot(readSnapshot):
            snapshot = readSnapshot
        case let .skipped(.captureSkipMarker(marker)):
            logger.debug("Skipping clip due to pasteboard skip marker: \(marker.rawValue, privacy: .public)")
            return
        case .skipped(.noTypes):
            logger.debug("Skipping clip with no pasteboard types")
            return
        }

        isCaptureInFlight = true
        let persistSnapshot = persistSnapshot
        Task { [weak self] in
            let result = await persistSnapshot(snapshot)
            self?.persistenceDidFinish(result)
        }
    }

    private func persistenceDidFinish(_ result: ClipboardPersistenceResult) {
        isCaptureInFlight = false
        if result == .noRestorablePayload {
            logger.debug("Skipping clip with no restorable payload")
        }

        // If the pasteboard changed while persistence was running, busy polls
        // deliberately left lastChangeCount untouched. Capture the latest value.
        guard isMonitoring else { return }
        pollClipboard()
    }

    nonisolated static func deriveTitle(
        stringValue: String?,
        availableTypes: [String],
        fileURLs: [String]?
    ) -> String {
        if let text = stringValue, !text.isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return String(trimmed.prefix(50))
            }
        }
        if let urls = fileURLs, let first = urls.first {
            return "[File: \(URL(string: first)?.lastPathComponent ?? first)]"
        }
        // Scan all available types, not just the first one. The leading type can
        // be an Apple-internal identifier that UTType does not resolve.
        let uttypes = availableTypes.compactMap { UTType($0) }
        if uttypes.contains(where: { $0.conforms(to: .image) }) { return "[Image]" }
        if uttypes.contains(where: { $0.conforms(to: .pdf) }) { return "[PDF]" }
        if uttypes.contains(where: { $0.conforms(to: .rtfd) }) { return "[RTFD]" }
        if uttypes.contains(where: { $0.conforms(to: .rtf) }) { return "[RTF]" }
        if uttypes.contains(where: { $0.conforms(to: .html) }) { return "[HTML]" }
        return "[Clipboard Data]"
    }
}
