import XCTest
import SwiftData
@testable import Yank

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ClipItem.self, Snippet.self, SnippetFolder.self,
            configurations: config
        )
        return ModelContext(container)
    }

    func testCapturesClipboardChange() throws {
        let context = try makeContext()
        let monitor = ClipboardMonitor(modelContext: context)
        monitor.start()

        // Write to actual pasteboard for testing
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("test capture", forType: .string)

        // Allow time for polling interval + MainActor dispatch
        let expectation = expectation(description: "clip captured")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let items = try context.fetch(FetchDescriptor<ClipItem>())
        XCTAssertGreaterThanOrEqual(items.count, 1)

        let captured = items.first(where: { $0.stringValue == "test capture" })
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.stringValue, "test capture")

        monitor.stop()
    }

    func testIgnoresSelfPaste() throws {
        let context = try makeContext()
        let monitor = ClipboardMonitor(modelContext: context)
        monitor.start()

        // Mirror PasteEngine pattern: block before write, update after
        monitor.skipLock.withLock { $0 = Int.max }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("self-pasted content", forType: .string)
        monitor.skipLock.withLock { $0 = pasteboard.changeCount }

        let expectation = expectation(description: "wait for poll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let items = try context.fetch(FetchDescriptor<ClipItem>())
        let selfPasted = items.first(where: { $0.stringValue == "self-pasted content" })
        XCTAssertNil(selfPasted, "Self-pasted content should not be captured")

        monitor.stop()
    }
}
