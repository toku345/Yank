import AppKit
import SwiftData
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
    typealias ClearHistory = @Sendable () async throws -> Void

    // Exposed (internal) so tests can assert the injected default is `.general`.
    let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    private let persistSnapshot: PersistSnapshot
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "ClipboardMonitor")

    private var isCaptureInFlight = false
    private var isMonitoring = false
    private var isShuttingDown = false
    private var persistenceTask: Task<Void, Never>?
    private var clearHistoryTask: Task<Void, Error>?

    init(
        pasteboard: NSPasteboard = .general,
        persistSnapshot: @escaping PersistSnapshot
    ) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.persistSnapshot = persistSnapshot
    }

    /// Creates a monitor backed by its own `ClipboardHistoryWriter`.
    /// The injected-persistence initializer is used when the caller must share
    /// a writer with other operations such as Clear All.
    convenience init(
        modelContainer: ModelContainer,
        pasteboard: NSPasteboard = .general,
        historyLimit: Int = ClipboardHistoryPolicy.defaultLimit
    ) {
        let writer = ClipboardHistoryWriter(
            modelContainer: modelContainer,
            historyLimit: historyLimit
        )
        self.init(
            pasteboard: pasteboard,
            persistSnapshot: { snapshot in await writer.persist(snapshot) }
        )
    }

    func start() {
        guard !isShuttingDown else { return }
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

    func stopAndDrain() async {
        beginShutdown()
        await finishShutdown()
    }

    func beginShutdown() {
        isShuttingDown = true
        stop()
    }

    func finishShutdown() async {
        let pendingPersistence = persistenceTask
        let pendingClear = clearHistoryTask
        await pendingPersistence?.value
        try? await pendingClear?.value
    }

    func clearHistory(using clearHistory: @escaping ClearHistory) async throws {
        guard !isShuttingDown else { return }
        if let clearHistoryTask {
            try await clearHistoryTask.value
            return
        }

        let shouldResumeMonitoring = isMonitoring
        stop()
        // Clear All is also a capture barrier. Discard pasteboard changes that
        // happened before confirmation so the current value is not reinserted.
        let captureBarrier = pasteboard.changeCount

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.persistenceTask?.value
            do {
                try await clearHistory()
                self.lastChangeCount = captureBarrier
                if shouldResumeMonitoring && !self.isShuttingDown {
                    self.start()
                }
            } catch {
                if shouldResumeMonitoring && !self.isShuttingDown {
                    self.start()
                }
                throw error
            }
        }
        clearHistoryTask = task
        defer { clearHistoryTask = nil }
        try await task.value
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
        persistenceTask = Task { [weak self] in
            let result = await persistSnapshot(snapshot)
            self?.persistenceDidFinish(result)
        }
    }

    private func persistenceDidFinish(_ result: ClipboardPersistenceResult) {
        isCaptureInFlight = false
        persistenceTask = nil
        if result == .noRestorablePayload {
            logger.debug("Skipping clip with no restorable payload")
        }

        // If the pasteboard changed while persistence was running, busy polls
        // deliberately left lastChangeCount untouched. Capture the latest value.
        guard isMonitoring else { return }
        pollClipboard()
    }

}
