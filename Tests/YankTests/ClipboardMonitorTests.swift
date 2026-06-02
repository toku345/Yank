import XCTest
import SwiftData
@testable import Yank

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ClipItem.self, configurations: config)
        return ModelContext(container)
    }

    func testCapturesClipboardChange() throws {
        let context = try makeContext()
        let monitor = ClipboardMonitor(modelContext: context)
        monitor.start()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        addTeardownBlock {
            monitor.stop()
            pasteboard.clearContents()
        }
        pasteboard.setString("test capture", forType: .string)

        let expectation = expectation(description: "clip captured")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let items = try context.fetch(FetchDescriptor<ClipItem>())
        let captured = items.first(where: { $0.stringValue == "test capture" })
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.stringValue, "test capture")
    }

    func testIgnoresSelfPaste() throws {
        let context = try makeContext()
        let monitor = ClipboardMonitor(modelContext: context)
        monitor.start()

        // Simulate PasteService: write with .fromYank marker
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        addTeardownBlock {
            monitor.stop()
            pasteboard.clearContents()
        }
        pasteboard.declareTypes([.string, .fromYank], owner: nil)
        pasteboard.setString("self-pasted content", forType: .string)
        pasteboard.setString("", forType: .fromYank)

        let expectation = expectation(description: "wait for poll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        let items = try context.fetch(FetchDescriptor<ClipItem>())
        let selfPasted = items.first(where: { $0.stringValue == "self-pasted content" })
        XCTAssertNil(selfPasted, "Self-pasted content should not be captured")
    }

    func testIgnoresCaptureSkipMarkers() throws {
        for marker in NSPasteboard.PasteboardType.captureSkipMarkers {
            let context = try makeContext()
            let monitor = ClipboardMonitor(modelContext: context)
            monitor.start()

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            addTeardownBlock {
                monitor.stop()
                pasteboard.clearContents()
            }

            let value = "sensitive content \(marker.rawValue)"
            pasteboard.declareTypes([.string, marker], owner: nil)
            pasteboard.setString(value, forType: .string)
            pasteboard.setString("", forType: marker)

            let expectation = expectation(description: "wait for poll \(marker.rawValue)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)

            let items = try context.fetch(FetchDescriptor<ClipItem>())
            let captured = items.first(where: { $0.stringValue == value })
            XCTAssertNil(captured, "Marked content should not be captured: \(marker.rawValue)")

            monitor.stop()
            pasteboard.clearContents()
        }
    }
}
