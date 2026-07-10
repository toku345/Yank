// swiftlint:disable file_length
import XCTest
import AppKit
import SwiftData
import SwiftUI
@testable import Yank

private struct InjectedSaveError: Error {}

private final class SaveController: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var failingCalls: Set<Int>
    private var contextIDs: Set<ObjectIdentifier> = []

    init(failingCalls: Set<Int> = []) {
        self.failingCalls = failingCalls
    }

    func save(_ context: ModelContext) throws {
        lock.lock()
        calls += 1
        let call = calls
        contextIDs.insert(ObjectIdentifier(context))
        let shouldFail = failingCalls.remove(call) != nil
        lock.unlock()

        if shouldFail { throw InjectedSaveError() }
        try context.save()
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    var contextCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return contextIDs.count
    }
}

@MainActor
private final class QueryProbeRecorder {
    private let initialExpectation: XCTestExpectation
    private let updateExpectation: XCTestExpectation
    private var observedInitial = false
    private var observedUpdate = false

    init(initialExpectation: XCTestExpectation, updateExpectation: XCTestExpectation) {
        self.initialExpectation = initialExpectation
        self.updateExpectation = updateExpectation
    }

    func record(_ count: Int) {
        if count == 0 && !observedInitial {
            observedInitial = true
            initialExpectation.fulfill()
        }
        if count == 1 && !observedUpdate {
            observedUpdate = true
            updateExpectation.fulfill()
        }
    }
}

private struct QueryCountProbe: View {
    @Query(sort: \ClipItem.createdAt, order: .reverse)
    private var items: [ClipItem]
    let recorder: QueryProbeRecorder

    var body: some View {
        Text("\(items.count)")
            .onAppear { recorder.record(items.count) }
            .onChange(of: items.count) { _, count in recorder.record(count) }
    }
}

@MainActor
private final class QueryValuesProbeRecorder {
    private let initialValues: [String]
    private let updatedValues: [String]
    private let initialExpectation: XCTestExpectation
    private let updateExpectation: XCTestExpectation
    private var observedInitial = false
    private var observedUpdate = false

    init(
        initialValues: [String],
        updatedValues: [String],
        initialExpectation: XCTestExpectation,
        updateExpectation: XCTestExpectation
    ) {
        self.initialValues = initialValues
        self.updatedValues = updatedValues
        self.initialExpectation = initialExpectation
        self.updateExpectation = updateExpectation
    }

    func record(_ values: [String]) {
        if values == initialValues && !observedInitial {
            observedInitial = true
            initialExpectation.fulfill()
        }
        if values == updatedValues && !observedUpdate {
            observedUpdate = true
            updateExpectation.fulfill()
        }
    }
}

private struct QueryValuesProbe: View {
    @Query(sort: \ClipItem.createdAt, order: .reverse)
    private var items: [ClipItem]
    let recorder: QueryValuesProbeRecorder

    private var values: [String] {
        items.compactMap(\.stringValue)
    }

    var body: some View {
        Text("\(items.count)")
            .onAppear { recorder.record(values) }
            .onChange(of: values) { _, values in recorder.record(values) }
    }
}

@MainActor
// swiftlint:disable:next type_body_length
final class ClipboardHistoryWriterTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ClipItem.self, configurations: config)
    }

    private func makeSnapshot(
        value: String? = "clipboard text",
        primaryType: String = "public.utf8-plain-text",
        availableTypes: [String]? = nil,
        createdAt: Date = Date(),
        rtfData: Data? = nil,
        rtfdData: Data? = nil,
        htmlData: Data? = nil,
        pdfData: Data? = nil,
        imageData: Data? = nil,
        fileURLs: [String]? = nil
    ) -> PasteboardSnapshot {
        PasteboardSnapshot(
            availableTypes: availableTypes ?? [primaryType],
            primaryType: primaryType,
            stringValue: value,
            rtfData: rtfData,
            rtfdData: rtfdData,
            htmlData: htmlData,
            pdfData: pdfData,
            imageData: imageData,
            fileURLs: fileURLs,
            createdAt: createdAt
        )
    }

    private func fetchItems(from container: ModelContainer) throws -> [ClipItem] {
        try ModelContext(container).fetch(FetchDescriptor<ClipItem>())
    }

    private func makeQueryWindow<Content: View>(rootView: Content) -> NSWindow {
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        return window
    }

    func testPersistsFullFidelityPayloadAndCaptureDateAcrossContexts() async throws {
        let container = try makeContainer()
        let writer = ClipboardHistoryWriter(modelContainer: container)
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let snapshot = makeSnapshot(
            value: "  clipboard text  ",
            createdAt: capturedAt,
            rtfData: Data([1]),
            rtfdData: Data([2]),
            htmlData: Data([3]),
            pdfData: Data([4]),
            imageData: Data([5]),
            fileURLs: ["file:///tmp/example.txt"]
        )

        let result = await writer.persist(snapshot)

        XCTAssertEqual(result, .saved(prunedCount: 0))
        let item = try XCTUnwrap(fetchItems(from: container).first)
        XCTAssertEqual(item.title, "clipboard text")
        XCTAssertEqual(item.stringValue, snapshot.stringValue)
        XCTAssertEqual(item.rtfData, snapshot.rtfData)
        XCTAssertEqual(item.rtfdData, snapshot.rtfdData)
        XCTAssertEqual(item.htmlData, snapshot.htmlData)
        XCTAssertEqual(item.pdfData, snapshot.pdfData)
        XCTAssertEqual(item.imageData, snapshot.imageData)
        XCTAssertEqual(item.fileURLs, snapshot.fileURLs)
        XCTAssertEqual(item.createdAt, capturedAt)
    }

    func testPersistsEachNonTextOnlyPayload() async throws {
        struct PayloadCase {
            let name: String
            let primaryType: NSPasteboard.PasteboardType
            var rtfData: Data?
            var rtfdData: Data?
            var htmlData: Data?
            var pdfData: Data?
            var imageData: Data?
            var fileURLs: [String]?
        }

        let cases = [
            PayloadCase(name: "RTF", primaryType: .rtf, rtfData: Data([1])),
            PayloadCase(name: "RTFD", primaryType: .rtfd, rtfdData: Data([2])),
            PayloadCase(name: "HTML", primaryType: .html, htmlData: Data([3])),
            PayloadCase(name: "PDF", primaryType: .pdf, pdfData: Data([4])),
            PayloadCase(name: "image", primaryType: .tiff, imageData: Data([5])),
            PayloadCase(
                name: "file URL",
                primaryType: .fileURL,
                fileURLs: ["file:///tmp/example.txt"]
            )
        ]

        for testCase in cases {
            let container = try makeContainer()
            let writer = ClipboardHistoryWriter(modelContainer: container)
            let snapshot = makeSnapshot(
                value: nil,
                primaryType: testCase.primaryType.rawValue,
                rtfData: testCase.rtfData,
                rtfdData: testCase.rtfdData,
                htmlData: testCase.htmlData,
                pdfData: testCase.pdfData,
                imageData: testCase.imageData,
                fileURLs: testCase.fileURLs
            )

            let result = await writer.persist(snapshot)
            let item = try XCTUnwrap(fetchItems(from: container).first, testCase.name)

            XCTAssertEqual(result, .saved(prunedCount: 0), testCase.name)
            XCTAssertNil(item.stringValue, testCase.name)
            XCTAssertEqual(item.rtfData, testCase.rtfData, testCase.name)
            XCTAssertEqual(item.rtfdData, testCase.rtfdData, testCase.name)
            XCTAssertEqual(item.htmlData, testCase.htmlData, testCase.name)
            XCTAssertEqual(item.pdfData, testCase.pdfData, testCase.name)
            XCTAssertEqual(item.imageData, testCase.imageData, testCase.name)
            XCTAssertEqual(item.fileURLs, testCase.fileURLs, testCase.name)
        }
    }

    func testMountedQueryObservesWriterSaveWithoutManualMerge() async throws {
        let container = try makeContainer()
        let writer = ClipboardHistoryWriter(modelContainer: container)
        let initialExpectation = expectation(description: "mounted query initially empty")
        let updateExpectation = expectation(description: "mounted query observed actor save")
        let recorder = QueryProbeRecorder(
            initialExpectation: initialExpectation,
            updateExpectation: updateExpectation
        )
        let window = makeQueryWindow(
            rootView: QueryCountProbe(recorder: recorder).modelContainer(container)
        )
        defer { window.contentView = nil }

        await fulfillment(of: [initialExpectation], timeout: 1.0)
        let result = await writer.persist(makeSnapshot())
        XCTAssertEqual(result, .saved(prunedCount: 0))
        await fulfillment(of: [updateExpectation], timeout: 1.0)
    }

    func testMountedQueryObservesBackgroundPruneDeletion() async throws {
        let container = try makeContainer()
        let seededDate = Date(timeIntervalSince1970: 1_700_000_000)
        let seedContext = ModelContext(container)
        for index in 0..<3 {
            seedContext.insert(ClipItem(
                title: "seed \(index)",
                primaryType: NSPasteboard.PasteboardType.string.rawValue,
                availableTypes: [NSPasteboard.PasteboardType.string.rawValue],
                stringValue: "seed \(index)",
                createdAt: seededDate.addingTimeInterval(TimeInterval(index))
            ))
        }
        try seedContext.save()

        let initialExpectation = expectation(description: "mounted query observed seeded history")
        let updateExpectation = expectation(description: "mounted query observed background prune")
        let recorder = QueryValuesProbeRecorder(
            initialValues: ["seed 2", "seed 1", "seed 0"],
            updatedValues: ["trigger", "seed 2"],
            initialExpectation: initialExpectation,
            updateExpectation: updateExpectation
        )
        let window = makeQueryWindow(
            rootView: QueryValuesProbe(recorder: recorder).modelContainer(container)
        )
        defer { window.contentView = nil }

        await fulfillment(of: [initialExpectation], timeout: 1.0)
        let writer = ClipboardHistoryWriter(modelContainer: container, historyLimit: 2)
        let result = await writer.persist(makeSnapshot(
            value: "trigger",
            createdAt: seededDate.addingTimeInterval(100)
        ))

        XCTAssertEqual(result, .saved(prunedCount: 2))
        await fulfillment(of: [updateExpectation], timeout: 1.0)
    }

    func testSkipsWhitespaceOnlySnapshotWithoutRestorablePayload() async throws {
        let container = try makeContainer()
        let writer = ClipboardHistoryWriter(modelContainer: container)
        let snapshot = makeSnapshot(value: "  \n\t ")

        let result = await writer.persist(snapshot)

        XCTAssertEqual(result, .noRestorablePayload)
        XCTAssertTrue(try fetchItems(from: container).isEmpty)
    }

    func testDeduplicatesOnlyAfterSuccessfulInsert() async throws {
        let container = try makeContainer()
        let saveController = SaveController(failingCalls: [1, 2])
        let writer = ClipboardHistoryWriter(
            modelContainer: container,
            saveContext: { try saveController.save($0) }
        )
        let snapshot = makeSnapshot()

        let failedResult = await writer.persist(snapshot)
        let successfulResult = await writer.persist(snapshot)
        let duplicateResult = await writer.persist(snapshot)

        XCTAssertEqual(failedResult, .failed)
        XCTAssertEqual(successfulResult, .saved(prunedCount: 0))
        XCTAssertEqual(duplicateResult, .duplicate)
        XCTAssertEqual(saveController.callCount, 3)
        XCTAssertEqual(try fetchItems(from: container).count, 1)
    }

    func testClearAllResetsFingerprintAfterSuccessfulDelete() async throws {
        let container = try makeContainer()
        let writer = ClipboardHistoryWriter(modelContainer: container)
        let snapshot = makeSnapshot()

        let firstResult = await writer.persist(snapshot)
        XCTAssertEqual(firstResult, .saved(prunedCount: 0))
        try await writer.clearAll()
        XCTAssertTrue(try fetchItems(from: container).isEmpty)

        let secondResult = await writer.persist(snapshot)
        XCTAssertEqual(secondResult, .saved(prunedCount: 0))
        XCTAssertEqual(try fetchItems(from: container).count, 1)
    }

    func testClearAllFailureRollsBackAndKeepsFingerprint() async throws {
        let container = try makeContainer()
        let saveController = SaveController(failingCalls: [2])
        let writer = ClipboardHistoryWriter(
            modelContainer: container,
            saveContext: { try saveController.save($0) }
        )
        let snapshot = makeSnapshot()

        let persistedResult = await writer.persist(snapshot)
        XCTAssertEqual(persistedResult, .saved(prunedCount: 0))
        do {
            try await writer.clearAll()
            XCTFail("Expected clearAll to throw")
        } catch is InjectedSaveError {
            // Expected.
        }

        XCTAssertEqual(try fetchItems(from: container).count, 1)
        let duplicateResult = await writer.persist(snapshot)
        XCTAssertEqual(duplicateResult, .duplicate)
    }

    func testRetriesInsertOnceAndReusesOneModelContext() async throws {
        let container = try makeContainer()
        let saveController = SaveController(failingCalls: [1])
        let writer = ClipboardHistoryWriter(
            modelContainer: container,
            saveContext: { try saveController.save($0) }
        )

        let firstResult = await writer.persist(makeSnapshot(value: "first"))
        let secondResult = await writer.persist(makeSnapshot(value: "second"))

        XCTAssertEqual(firstResult, .saved(prunedCount: 0))
        XCTAssertEqual(secondResult, .saved(prunedCount: 0))
        XCTAssertEqual(saveController.callCount, 3)
        XCTAssertEqual(saveController.contextCount, 1)
        XCTAssertEqual(try fetchItems(from: container).count, 2)
    }

    func testPrunesAllOverflowOldestFirstAndRetriesPruneOnce() async throws {
        let container = try makeContainer()
        let seedContext = ModelContext(container)
        let seededDate = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<5 {
            seedContext.insert(ClipItem(
                title: "seed \(index)",
                primaryType: "public.utf8-plain-text",
                availableTypes: ["public.utf8-plain-text"],
                stringValue: "seed \(index)",
                createdAt: seededDate.addingTimeInterval(TimeInterval(index))
            ))
        }
        try seedContext.save()

        // Call 1 saves the insert, call 2 is the first prune attempt, and call 3
        // is its single retry.
        let saveController = SaveController(failingCalls: [2])
        let writer = ClipboardHistoryWriter(
            modelContainer: container,
            historyLimit: 2,
            saveContext: { try saveController.save($0) }
        )
        let snapshot = makeSnapshot(
            value: "newest",
            createdAt: seededDate.addingTimeInterval(100)
        )

        let result = await writer.persist(snapshot)

        XCTAssertEqual(result, .saved(prunedCount: 4))
        XCTAssertEqual(saveController.callCount, 3)
        let items = try ModelContext(container).fetch(FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\ClipItem.createdAt, order: .reverse)]
        ))
        XCTAssertEqual(items.compactMap(\.stringValue), ["newest", "seed 4"])
    }

    func testPruneFailureKeepsInsertAndFingerprintThenRecoversOnNextCapture() async throws {
        let container = try makeContainer()
        let seedContext = ModelContext(container)
        let seededDate = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<3 {
            seedContext.insert(ClipItem(
                title: "seed \(index)",
                primaryType: "public.utf8-plain-text",
                availableTypes: ["public.utf8-plain-text"],
                stringValue: "seed \(index)",
                createdAt: seededDate.addingTimeInterval(TimeInterval(index))
            ))
        }
        try seedContext.save()

        let saveController = SaveController(failingCalls: [2, 3])
        let writer = ClipboardHistoryWriter(
            modelContainer: container,
            historyLimit: 2,
            saveContext: { try saveController.save($0) }
        )
        let firstSnapshot = makeSnapshot(
            value: "first capture",
            createdAt: seededDate.addingTimeInterval(100)
        )

        let firstResult = await writer.persist(firstSnapshot)
        let duplicateResult = await writer.persist(firstSnapshot)
        let itemsAfterFailure = try fetchItems(from: container)

        XCTAssertEqual(firstResult, .saved(prunedCount: 0))
        XCTAssertEqual(duplicateResult, .duplicate)
        XCTAssertEqual(itemsAfterFailure.count, 4)
        XCTAssertEqual(itemsAfterFailure.filter { $0.stringValue == "first capture" }.count, 1)

        let recoveryResult = await writer.persist(makeSnapshot(
            value: "second capture",
            createdAt: seededDate.addingTimeInterval(101)
        ))

        XCTAssertEqual(recoveryResult, .saved(prunedCount: 3))
        XCTAssertEqual(saveController.callCount, 5)
        let recoveredItems = try ModelContext(container).fetch(FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\ClipItem.createdAt, order: .reverse)]
        ))
        XCTAssertEqual(recoveredItems.compactMap(\.stringValue), ["second capture", "first capture"])
    }
}
