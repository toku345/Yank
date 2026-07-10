import Foundation
import SwiftData
import UniformTypeIdentifiers
import os.log

enum ClipboardHistoryPolicy {
    static let defaultLimit = 1_000
}

struct PasteboardSnapshot: Sendable {
    let availableTypes: [String]
    let primaryType: String
    let stringValue: String?
    let rtfData: Data?
    let rtfdData: Data?
    let htmlData: Data?
    let pdfData: Data?
    let imageData: Data?
    let fileURLs: [String]?
    let createdAt: Date

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

    var hasRestorablePayload: Bool {
        stringValue != nil || rtfData != nil || rtfdData != nil
            || htmlData != nil || pdfData != nil || imageData != nil
            || fileURLs?.isEmpty == false
    }

    var normalized: PasteboardSnapshot {
        let normalizedString = stringValue.flatMap { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        }
        return PasteboardSnapshot(
            availableTypes: availableTypes,
            primaryType: primaryType,
            stringValue: normalizedString,
            rtfData: rtfData,
            rtfdData: rtfdData,
            htmlData: htmlData,
            pdfData: pdfData,
            imageData: imageData,
            fileURLs: fileURLs,
            createdAt: createdAt
        )
    }
}

enum ClipboardPersistenceResult: Equatable, Sendable {
    case saved(prunedCount: Int)
    case duplicate
    case noRestorablePayload
    case failed
}

actor ClipboardHistoryWriter {
    typealias SaveContext = @Sendable (ModelContext) throws -> Void

    private let modelContainer: ModelContainer
    private let historyLimit: Int
    private let saveContext: SaveContext
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "ClipboardHistoryWriter")

    private var modelContext: ModelContext?
    private var lastPersistedFingerprint: Int?

    init(
        modelContainer: ModelContainer,
        historyLimit: Int = ClipboardHistoryPolicy.defaultLimit,
        saveContext: @escaping SaveContext = { try $0.save() }
    ) {
        self.modelContainer = modelContainer
        self.historyLimit = max(1, historyLimit)
        self.saveContext = saveContext
    }

    func persist(_ capturedSnapshot: PasteboardSnapshot) -> ClipboardPersistenceResult {
        let snapshot = capturedSnapshot.normalized
        guard snapshot.hasRestorablePayload else { return .noRestorablePayload }

        let fingerprint = snapshot.fingerprint
        guard fingerprint != lastPersistedFingerprint else { return .duplicate }

        let title = Self.deriveTitle(
            stringValue: snapshot.stringValue,
            availableTypes: snapshot.availableTypes,
            fileURLs: snapshot.fileURLs
        )
        let context = persistenceContext()
        guard insert(snapshot, title: title, into: context) else { return .failed }

        // The item is durable at this point. A prune failure must not cause a
        // later poll to insert the same clipboard payload again.
        lastPersistedFingerprint = fingerprint
        let prunedCount = pruneOverflow(in: context) ?? 0
        logger.debug(
            "Captured clip type=\(snapshot.primaryType, privacy: .public), pruned=\(prunedCount, privacy: .public)"
        )
        return .saved(prunedCount: prunedCount)
    }

    func clearAll() throws {
        let context = persistenceContext()
        do {
            let items = try context.fetch(FetchDescriptor<ClipItem>())
            for item in items {
                context.delete(item)
            }
            try saveContext(context)
            lastPersistedFingerprint = nil
        } catch {
            context.rollback()
            logger.error(
                "Failed to clear clipboard history: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    static func deriveTitle(
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

    private func persistenceContext() -> ModelContext {
        if let modelContext { return modelContext }

        // Construct on the actor executor rather than in init(), which normally
        // runs on the caller's (MainActor) executor.
        let context = ModelContext(modelContainer)
        modelContext = context
        return context
    }

    private func insert(
        _ snapshot: PasteboardSnapshot,
        title: String,
        into context: ModelContext
    ) -> Bool {
        for attempt in 1...2 {
            context.insert(makeClipItem(from: snapshot, title: title))
            do {
                try saveContext(context)
                return true
            } catch {
                context.rollback()
                if attempt == 2 {
                    logger.error(
                        "Failed to save clipboard history after retry: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
        return false
    }

    private func pruneOverflow(in context: ModelContext) -> Int? {
        for attempt in 1...2 {
            do {
                var descriptor = FetchDescriptor<ClipItem>(
                    sortBy: [SortDescriptor(\ClipItem.createdAt, order: .reverse)]
                )
                descriptor.fetchOffset = historyLimit
                let overflowItems = try context.fetch(descriptor)
                guard !overflowItems.isEmpty else { return 0 }

                for item in overflowItems {
                    context.delete(item)
                }
                try saveContext(context)
                return overflowItems.count
            } catch {
                context.rollback()
                if attempt == 2 {
                    logger.error(
                        "Failed to prune clipboard history after retry: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
        return nil
    }

    private func makeClipItem(from snapshot: PasteboardSnapshot, title: String) -> ClipItem {
        ClipItem(
            title: title,
            primaryType: snapshot.primaryType,
            availableTypes: snapshot.availableTypes,
            stringValue: snapshot.stringValue,
            rtfData: snapshot.rtfData,
            rtfdData: snapshot.rtfdData,
            htmlData: snapshot.htmlData,
            pdfData: snapshot.pdfData,
            imageData: snapshot.imageData,
            fileURLs: snapshot.fileURLs,
            createdAt: snapshot.createdAt
        )
    }
}
