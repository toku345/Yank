// swiftlint:disable file_length
import XCTest
import AppKit
import SwiftData
@testable import Yank

private enum ClearHistoryTestError: Error {
    case failed
}

private actor PersistenceGate {
    typealias DidRecord = @Sendable (Int) -> Void

    private var snapshots: [PasteboardSnapshot] = []
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private var firstReleased = false
    private let didRecord: DidRecord

    init(didRecord: @escaping DidRecord = { _ in }) {
        self.didRecord = didRecord
    }

    func persist(_ snapshot: PasteboardSnapshot) async -> ClipboardPersistenceResult {
        await waitBeforePersisting(snapshot)
        return .saved(prunedCount: 0)
    }

    func waitBeforePersisting(_ snapshot: PasteboardSnapshot) async {
        snapshots.append(snapshot)
        didRecord(snapshots.count)
        if snapshots.count == 1 && !firstReleased {
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
    }

    func releaseFirst() {
        firstReleased = true
        firstContinuation?.resume()
        firstContinuation = nil
    }

    func values() -> [String?] {
        snapshots.map(\.stringValue)
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func append(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

@MainActor
// swiftlint:disable:next type_body_length
final class ClipboardMonitorTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ClipItem.self, configurations: config)
    }

    private func writeString(_ value: String, to pasteboard: NSPasteboard) {
        pasteboard.declareTypes([.string], owner: nil)
        XCTAssertTrue(pasteboard.setString(value, forType: .string))
    }

    private func waitForClipboardPoll(description: String = "wait for poll") {
        let expectation = expectation(description: description)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    // Guards the production default: AppCoordinator injects persistence without
    // a pasteboard argument, so capture must target .general. No start() call --
    // this only inspects the injected reference, so it has no side effects.
    func testUsesGeneralPasteboardByDefault() {
        let monitor = ClipboardMonitor(persistSnapshot: { _ in .failed })
        XCTAssertTrue(monitor.pasteboard === NSPasteboard.general)
    }

    func testCapturesClipboardChange() throws {
        let container = try makeContainer()
        let pasteboard = makeTestPasteboard()
        let monitor = ClipboardMonitor(modelContainer: container, pasteboard: pasteboard)
        monitor.start()

        addTeardownBlock { monitor.stop() }
        writeString("test capture", to: pasteboard)

        waitForClipboardPoll(description: "clip captured")

        let items = try ModelContext(container).fetch(FetchDescriptor<ClipItem>())
        let captured = items.first(where: { $0.stringValue == "test capture" })
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.stringValue, "test capture")
    }

    func testIgnoresSelfPaste() throws {
        let container = try makeContainer()
        let pasteboard = makeTestPasteboard()
        let monitor = ClipboardMonitor(modelContainer: container, pasteboard: pasteboard)
        monitor.start()

        // Simulate PasteService: write with .fromYank marker
        addTeardownBlock { monitor.stop() }
        pasteboard.declareTypes([.string, .fromYank], owner: nil)
        pasteboard.setString("self-pasted content", forType: .string)
        pasteboard.setString("", forType: .fromYank)

        waitForClipboardPoll()

        let items = try ModelContext(container).fetch(FetchDescriptor<ClipItem>())
        let selfPasted = items.first(where: { $0.stringValue == "self-pasted content" })
        XCTAssertNil(selfPasted, "Self-pasted content should not be captured")
    }

    func testIgnoresCaptureSkipMarkers() throws {
        let expectedMarkerRawValues = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType"
        ]
        XCTAssertEqual(
            Set(NSPasteboard.PasteboardType.externalCaptureSkipMarkers.map(\.rawValue)),
            Set(expectedMarkerRawValues)
        )

        for markerRawValue in expectedMarkerRawValues {
            let marker = NSPasteboard.PasteboardType(markerRawValue)
            let container = try makeContainer()
            let pasteboard = makeTestPasteboard()
            let monitor = ClipboardMonitor(modelContainer: container, pasteboard: pasteboard)
            monitor.start()

            defer { monitor.stop() }

            let unmarkedValue = "unmarked content \(marker.rawValue)"
            writeString(unmarkedValue, to: pasteboard)
            waitForClipboardPoll(description: "capture control \(marker.rawValue)")

            var items = try ModelContext(container).fetch(FetchDescriptor<ClipItem>())
            let unmarked = items.first(where: { $0.stringValue == unmarkedValue })
            XCTAssertNotNil(unmarked, "Unmarked content should be captured: \(marker.rawValue)")
            let itemCountAfterUnmarkedCapture = items.count

            pasteboard.clearContents()
            let value = "sensitive content \(marker.rawValue)"
            pasteboard.declareTypes([.string, marker], owner: nil)
            XCTAssertTrue(pasteboard.setString(value, forType: .string))
            XCTAssertTrue(pasteboard.setString("", forType: marker))
            XCTAssertTrue(pasteboard.types?.contains(.string) == true)
            XCTAssertTrue(pasteboard.types?.contains(marker) == true)

            waitForClipboardPoll(description: "skip marker \(marker.rawValue)")

            items = try ModelContext(container).fetch(FetchDescriptor<ClipItem>())
            let captured = items.first(where: { $0.stringValue == value })
            XCTAssertNil(captured, "Marked content should not be captured: \(marker.rawValue)")
            XCTAssertEqual(
                items.count,
                itemCountAfterUnmarkedCapture,
                "Marked content should not add any item: \(marker.rawValue)"
            )
        }
    }

    func testPrunesOldestItemsWhenHistoryLimitIsExceeded() throws {
        let container = try makeContainer()
        let pasteboard = makeTestPasteboard()
        let monitor = ClipboardMonitor(modelContainer: container, pasteboard: pasteboard, historyLimit: 2)
        monitor.start()

        addTeardownBlock { monitor.stop() }

        writeString("oldest item", to: pasteboard)
        waitForClipboardPoll(description: "oldest captured")

        pasteboard.clearContents()
        writeString("middle item", to: pasteboard)
        waitForClipboardPoll(description: "middle captured")

        pasteboard.clearContents()
        writeString("newest item", to: pasteboard)
        waitForClipboardPoll(description: "newest captured")

        let descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\ClipItem.createdAt, order: .reverse)]
        )
        let items = try ModelContext(container).fetch(descriptor)
        let values = items.compactMap(\.stringValue)

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(values.contains("newest item"))
        XCTAssertTrue(values.contains("middle item"))
        XCTAssertFalse(values.contains("oldest item"))
    }

    func testPrunesAllSeededOverflowItemsAfterCapture() throws {
        let container = try makeContainer()
        let seedContext = ModelContext(container)
        let seededDate = Date(timeIntervalSinceNow: -1_000)
        for index in 0..<7 {
            seedContext.insert(ClipItem(
                title: "seed \(index)",
                primaryType: NSPasteboard.PasteboardType.string.rawValue,
                availableTypes: [NSPasteboard.PasteboardType.string.rawValue],
                stringValue: "seed \(index)",
                createdAt: seededDate.addingTimeInterval(TimeInterval(index))
            ))
        }
        try seedContext.save()

        let pasteboard = makeTestPasteboard()
        let monitor = ClipboardMonitor(
            modelContainer: container,
            pasteboard: pasteboard,
            historyLimit: 2
        )
        monitor.start()

        addTeardownBlock { monitor.stop() }
        writeString("trigger item", to: pasteboard)
        waitForClipboardPoll(description: "trigger captured and overflow pruned")

        let descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\ClipItem.createdAt, order: .reverse)]
        )
        let items = try ModelContext(container).fetch(descriptor)
        let values = items.compactMap(\.stringValue)

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(values.contains("trigger item"))
        XCTAssertTrue(values.contains("seed 6"))
        XCTAssertFalse(values.contains("seed 0"))
    }

    func testBusyPollLeavesChangePendingAndRepollsAfterPersistence() async {
        let pasteboard = makeTestPasteboard()
        let firstStarted = expectation(description: "first persistence started")
        let secondStarted = expectation(description: "second persistence started")
        let gate = PersistenceGate { count in
            if count == 1 { firstStarted.fulfill() }
            if count == 2 { secondStarted.fulfill() }
        }
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            persistSnapshot: { snapshot in await gate.persist(snapshot) }
        )
        monitor.start()
        addTeardownBlock { monitor.stop() }

        writeString("first", to: pasteboard)
        monitor.pollClipboard()
        await fulfillment(of: [firstStarted], timeout: 1.0)

        pasteboard.clearContents()
        writeString("second", to: pasteboard)
        monitor.pollClipboard()
        var values = await gate.values()
        XCTAssertEqual(values, ["first"])

        await gate.releaseFirst()
        await fulfillment(of: [secondStarted], timeout: 1.0)
        values = await gate.values()
        XCTAssertEqual(values, ["first", "second"])
    }

    func testClearHistoryWaitsForInFlightCaptureAndDiscardsPendingChange() async throws {
        let container = try makeContainer()
        let seedContext = ModelContext(container)
        seedContext.insert(ClipItem(
            title: "existing",
            primaryType: NSPasteboard.PasteboardType.string.rawValue,
            availableTypes: [NSPasteboard.PasteboardType.string.rawValue],
            stringValue: "existing"
        ))
        try seedContext.save()

        let pasteboard = makeTestPasteboard()
        let firstStarted = expectation(description: "in-flight persistence started")
        let gate = PersistenceGate { count in
            if count == 1 { firstStarted.fulfill() }
        }
        let writer = ClipboardHistoryWriter(modelContainer: container)
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            persistSnapshot: { snapshot in
                await gate.waitBeforePersisting(snapshot)
                return await writer.persist(snapshot)
            }
        )
        monitor.start()
        defer { monitor.stop() }

        writeString("first", to: pasteboard)
        monitor.pollClipboard()
        await fulfillment(of: [firstStarted], timeout: 1.0)
        pasteboard.clearContents()
        writeString("second", to: pasteboard)
        monitor.pollClipboard()

        let clearStarted = expectation(description: "clear history requested")
        let clearTask = Task {
            clearStarted.fulfill()
            try await monitor.clearHistory { try await writer.clearAll() }
        }
        await fulfillment(of: [clearStarted], timeout: 1.0)
        await gate.releaseFirst()
        try await clearTask.value

        monitor.pollClipboard()
        await monitor.stopAndDrain()

        let persistedValues = await gate.values()
        XCTAssertEqual(persistedValues, ["first"])
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<ClipItem>()).isEmpty)
    }

    func testClearHistoryFailureResumesAndCapturesPendingChange() async throws {
        let pasteboard = makeTestPasteboard()
        let persistenceStarted = expectation(description: "pending change captured after clear failure")
        let gate = PersistenceGate { count in
            if count == 1 { persistenceStarted.fulfill() }
        }
        await gate.releaseFirst()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            persistSnapshot: { snapshot in await gate.persist(snapshot) }
        )
        monitor.start()

        writeString("pending after failed clear", to: pasteboard)
        do {
            try await monitor.clearHistory { throw ClearHistoryTestError.failed }
            XCTFail("Expected clearHistory to throw")
        } catch ClearHistoryTestError.failed {
            // Expected.
        }

        monitor.pollClipboard()
        await fulfillment(of: [persistenceStarted], timeout: 1.0)
        await monitor.stopAndDrain()

        let values = await gate.values()
        XCTAssertEqual(values, ["pending after failed clear"])
    }

    func testStopAndDrainWaitsForInFlightPersistence() async throws {
        let container = try makeContainer()
        let pasteboard = makeTestPasteboard()
        let persistenceStarted = expectation(description: "persistence started")
        let gate = PersistenceGate { count in
            if count == 1 { persistenceStarted.fulfill() }
        }
        let events = EventRecorder()
        let writer = ClipboardHistoryWriter(modelContainer: container)
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            persistSnapshot: { snapshot in
                events.append("persist-start")
                await gate.waitBeforePersisting(snapshot)
                let result = await writer.persist(snapshot)
                events.append("persist-finish")
                return result
            }
        )
        monitor.start()

        writeString("shutdown capture", to: pasteboard)
        monitor.pollClipboard()
        await fulfillment(of: [persistenceStarted], timeout: 1.0)

        let drainStarted = expectation(description: "drain requested")
        let drainTask = Task {
            drainStarted.fulfill()
            await monitor.stopAndDrain()
            events.append("drain-finish")
        }
        await fulfillment(of: [drainStarted], timeout: 1.0)
        await gate.releaseFirst()
        await drainTask.value

        XCTAssertEqual(events.values, ["persist-start", "persist-finish", "drain-finish"])
        let items = try ModelContext(container).fetch(FetchDescriptor<ClipItem>())
        XCTAssertEqual(items.compactMap(\.stringValue), ["shutdown capture"])
    }

    func testApplicationShouldTerminateRepliesOnceAfterDrain() async {
        let events = EventRecorder()
        let finishGate = AsyncGate()
        let finishStarted = expectation(description: "finish shutdown started")
        let replied = expectation(description: "termination reply sent")
        let application = NSApplication.shared
        let delegate = AppDelegate(
            coordinator: AppCoordinator(),
            beginShutdown: { events.append("begin") },
            finishShutdown: {
                events.append("finish-start")
                finishStarted.fulfill()
                await finishGate.wait()
                events.append("finish-end")
            },
            replyToTermination: { replyingApplication, shouldTerminate in
                XCTAssertTrue(replyingApplication === application)
                XCTAssertTrue(shouldTerminate)
                events.append("reply")
                replied.fulfill()
            }
        )

        XCTAssertEqual(delegate.applicationShouldTerminate(application), .terminateLater)
        XCTAssertEqual(delegate.applicationShouldTerminate(application), .terminateLater)
        await fulfillment(of: [finishStarted], timeout: 1.0)
        XCTAssertEqual(events.values, ["begin", "finish-start"])

        await finishGate.release()
        await fulfillment(of: [replied], timeout: 1.0)
        await Task.yield()

        XCTAssertEqual(events.values, ["begin", "finish-start", "finish-end", "reply"])
        XCTAssertEqual(delegate.applicationShouldTerminate(application), .terminateNow)
        XCTAssertEqual(events.values.filter { $0 == "reply" }.count, 1)
    }
}
