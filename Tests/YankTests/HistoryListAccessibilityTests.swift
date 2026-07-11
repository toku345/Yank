import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Yank

@MainActor
final class HistoryListAccessibilityTests: XCTestCase {
    func testRowsExposeSelectionAndRouteAccessibilityPress() async throws {
        let fixture = try makeFixture()
        defer {
            fixture.window.orderOut(nil)
            fixture.window.contentView = nil
        }

        let newestButton = try await requireAccessibilityButton(
            labelled: fixture.newest.title,
            in: fixture.hostingView
        )
        let olderButton = try await requireAccessibilityButton(
            labelled: fixture.older.title,
            in: fixture.hostingView
        )

        XCTAssertEqual(
            stringValue(newestButton, selector: "accessibilityRole"),
            "AXButton"
        )
        XCTAssertEqual(
            stringValue(newestButton, selector: "accessibilityLabel"),
            fixture.newest.title
        )
        XCTAssertTrue(isAccessibilitySelected(newestButton))
        XCTAssertFalse(isAccessibilitySelected(olderButton))
        XCTAssertTrue(
            boolValue(olderButton, selector: "accessibilityPerformPress")
        )

        let didActivateOlderItem = await waitUntil {
            fixture.activationRecorder.itemID == fixture.older.persistentModelID
                && fixture.viewerState.selectedID == fixture.older.persistentModelID
        }
        XCTAssertTrue(didActivateOlderItem)

        let selectedOlderButton = try await requireAccessibilityButton(
            labelled: fixture.older.title,
            in: fixture.hostingView
        )
        XCTAssertTrue(isAccessibilitySelected(selectedOlderButton))
    }

    private final class ActivationRecorder {
        var itemID: PersistentIdentifier?
    }

    private struct Fixture {
        let container: ModelContainer
        let newest: ClipItem
        let older: ClipItem
        let viewerState: ViewerState
        let activationRecorder: ActivationRecorder
        let hostingView: NSHostingView<HistoryListView>
        let window: NSWindow
    }

    private func makeFixture() throws -> Fixture {
        let container = try makeContainer()
        let context = ModelContext(container)
        let newest = makeItem(title: "Newest clip", timestamp: 2)
        let older = makeItem(title: "Older clip", timestamp: 1)
        context.insert(newest)
        context.insert(older)
        try context.save()

        let viewerState = ViewerState()
        viewerState.replaceItems(with: [
            newest.persistentModelID,
            older.persistentModelID
        ])
        let activationRecorder = ActivationRecorder()
        let hostingView = NSHostingView(
            rootView: HistoryListView(
                items: [newest, older],
                viewerState: viewerState,
                onItemTap: { item in
                    activationRecorder.itemID = item.persistentModelID
                }
            )
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.orderFrontRegardless()
        return Fixture(
            container: container,
            newest: newest,
            older: older,
            viewerState: viewerState,
            activationRecorder: activationRecorder,
            hostingView: hostingView,
            window: window
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ClipItem.self,
            configurations: config
        )
    }

    private func makeItem(title: String, timestamp: TimeInterval) -> ClipItem {
        ClipItem(
            title: title,
            primaryType: "public.utf8-plain-text",
            availableTypes: ["public.utf8-plain-text"],
            stringValue: title,
            createdAt: Date(timeIntervalSince1970: timestamp)
        )
    }

    private func accessibilityButton(
        labelled label: String,
        in root: any NSAccessibilityProtocol
    ) async -> NSObject? {
        for _ in 0..<100 {
            if let button = findAccessibilityButton(
                labelled: label,
                in: root
            ) {
                return button
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    private func requireAccessibilityButton(
        labelled label: String,
        in root: any NSAccessibilityProtocol
    ) async throws -> NSObject {
        let button = await accessibilityButton(labelled: label, in: root)
        return try XCTUnwrap(
            button,
            "\(label) history row was not exposed to accessibility"
        )
    }

    private func findAccessibilityButton(
        labelled label: String,
        in root: any NSAccessibilityProtocol
    ) -> NSObject? {
        var pending: [Any] = [root]
        var visited: Set<ObjectIdentifier> = []

        while let candidate = pending.popLast() {
            let identifier = ObjectIdentifier(candidate as AnyObject)
            guard visited.insert(identifier).inserted else { continue }
            if let object = candidate as? NSObject,
               stringValue(object, selector: "accessibilityRole") == "AXButton",
               stringValue(object, selector: "accessibilityLabel") == label {
                return object
            }
            pending.append(contentsOf: accessibilityChildren(of: candidate))
        }
        return nil
    }

    private func accessibilityChildren(of candidate: Any) -> [Any] {
        if let element = candidate as? any NSAccessibilityProtocol {
            return element.accessibilityChildren() ?? []
        }
        guard let object = candidate as? NSObject else { return [] }
        let selector = NSSelectorFromString("accessibilityChildren")
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue()
                as? [Any] else {
            return []
        }
        return value
    }

    private func isAccessibilitySelected(_ element: NSObject) -> Bool {
        boolValue(element, selector: "isAccessibilitySelected")
    }

    private func stringValue(
        _ object: NSObject,
        selector selectorName: String
    ) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? String
    }

    private func boolValue(
        _ object: NSObject,
        selector selectorName: String
    ) -> Bool {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        let getter = unsafeBitCast(object.method(for: selector), to: Getter.self)
        return getter(object, selector)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
}
