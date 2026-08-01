import SwiftData
import XCTest
@testable import Yank

@MainActor
final class ViewerPanelControllerTests: XCTestCase {
    private enum TestFailure: Error {
        case loadFailed
    }

    func testDefaultLoader_sortsSavedItemsNewestFirst() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let oldest = makeItem(title: "Oldest", timestamp: 1)
        let newest = makeItem(title: "Newest", timestamp: 3)
        let middle = makeItem(title: "Middle", timestamp: 2)
        [oldest, newest, middle].forEach(context.insert)
        try context.save()

        let loadedIDs = try ViewerPanelController.loadSavedHistoryIDs(
            from: container
        )

        let expectedIDs = [newest, middle, oldest].map(\.persistentModelID)
        XCTAssertEqual(loadedIDs, expectedIDs)
    }

    func testShow_replacesStaleIDsAndResetsValidSelectionToNewest() throws {
        let fixture = try makeItemFixture(count: 3)
        let newestID = fixture.items[0].persistentModelID
        let olderID = fixture.items[1].persistentModelID
        let staleID = fixture.items[2].persistentModelID
        let loadedIDs = [newestID, olderID]
        let state = ViewerState()
        state.itemIDs = [staleID, olderID]
        state.selectedID = olderID
        var presentationCount = 0

        let controller = ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            loadHistoryIDs: { loadedIDs },
            reportLoadFailure: { error in
                XCTFail("Unexpected load failure: \(error)")
            },
            presentPanel: { _ in
                presentationCount += 1
                XCTAssertEqual(state.itemIDs, loadedIDs)
                XCTAssertEqual(state.selectedID, newestID)
            }
        )

        XCTAssertTrue(controller.show())
        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(state.itemIDs, loadedIDs)
        XCTAssertEqual(state.selectedID, newestID)
    }

    func testShow_preservesSnippetsTabAndResetsHistorySelection() throws {
        let fixture = try makeItemFixture(count: 2)
        let newestID = fixture.items[0].persistentModelID
        let olderID = fixture.items[1].persistentModelID
        let loadedIDs = [newestID, olderID]
        let state = ViewerState()
        state.selectedTab = .snippets
        state.itemIDs = loadedIDs
        state.selectedID = olderID
        var presentationCount = 0

        let controller = ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            loadHistoryIDs: { loadedIDs },
            reportLoadFailure: { error in
                XCTFail("Unexpected load failure: \(error)")
            },
            presentPanel: { _ in presentationCount += 1 }
        )

        XCTAssertTrue(controller.show())
        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(state.selectedTab, .snippets)
        XCTAssertEqual(state.selectedID, newestID)
    }

    func testShow_emptySnapshotClearsStateAndPresentsEmptyViewer() throws {
        let fixture = try makeItemFixture(count: 1)
        let state = ViewerState()
        state.itemIDs = fixture.items.map(\.persistentModelID)
        state.selectedID = state.itemIDs.first
        var presentationCount = 0

        let controller = ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            loadHistoryIDs: { [] },
            reportLoadFailure: { error in
                XCTFail("Unexpected load failure: \(error)")
            },
            presentPanel: { _ in
                presentationCount += 1
                XCTAssertTrue(state.itemIDs.isEmpty)
                XCTAssertNil(state.selectedID)
            }
        )

        XCTAssertTrue(controller.show())
        XCTAssertEqual(presentationCount, 1)
        XCTAssertTrue(state.itemIDs.isEmpty)
        XCTAssertNil(state.selectedID)
    }

    func testShow_failureClearsStateBeforeReportingAndDoesNotPresent() throws {
        let fixture = try makeItemFixture(count: 1)
        let state = ViewerState()
        state.itemIDs = fixture.items.map(\.persistentModelID)
        state.selectedID = state.itemIDs.first
        var reportCount = 0
        var presentationCount = 0

        let controller = ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            loadHistoryIDs: { throw TestFailure.loadFailed },
            reportLoadFailure: { error in
                reportCount += 1
                XCTAssertTrue(error is TestFailure)
                XCTAssertTrue(state.itemIDs.isEmpty)
                XCTAssertNil(state.selectedID)
            },
            presentPanel: { _ in presentationCount += 1 }
        )

        XCTAssertFalse(controller.show())
        XCTAssertEqual(reportCount, 1)
        XCTAssertEqual(presentationCount, 0)
        XCTAssertTrue(state.itemIDs.isEmpty)
        XCTAssertNil(state.selectedID)
    }

    func testShow_failurePreservesSnippetsTabAndDoesNotPresent() throws {
        let fixture = try makeItemFixture(count: 1)
        let state = ViewerState()
        state.selectedTab = .snippets
        state.itemIDs = fixture.items.map(\.persistentModelID)
        state.selectedID = state.itemIDs.first
        var reportCount = 0
        var presentationCount = 0

        let controller = ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            loadHistoryIDs: { throw TestFailure.loadFailed },
            reportLoadFailure: { _ in reportCount += 1 },
            presentPanel: { _ in presentationCount += 1 }
        )

        XCTAssertFalse(controller.show())
        XCTAssertEqual(reportCount, 1)
        XCTAssertEqual(presentationCount, 0)
        XCTAssertEqual(state.selectedTab, .snippets)
        XCTAssertTrue(state.itemIDs.isEmpty)
        XCTAssertNil(state.selectedID)
    }

    func testShow_failureAfterSuccessDoesNotPresentExistingPanelAgain() throws {
        let fixture = try makeItemFixture(count: 2)
        let loadedIDs = fixture.items.map(\.persistentModelID)
        let state = ViewerState()
        var loadCount = 0
        var reportCount = 0
        var presentationCount = 0

        let controller = ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            loadHistoryIDs: {
                loadCount += 1
                if loadCount == 1 {
                    return loadedIDs
                }
                throw TestFailure.loadFailed
            },
            reportLoadFailure: { _ in
                reportCount += 1
                XCTAssertTrue(state.itemIDs.isEmpty)
                XCTAssertNil(state.selectedID)
            },
            presentPanel: { _ in presentationCount += 1 }
        )

        XCTAssertTrue(controller.show())
        XCTAssertEqual(presentationCount, 1)

        XCTAssertFalse(controller.show())
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(reportCount, 1)
        XCTAssertEqual(presentationCount, 1)
        XCTAssertTrue(state.itemIDs.isEmpty)
        XCTAssertNil(state.selectedID)
    }

    func testShow_synchronizesOneThousandItemsBeforePresentation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let items = (0..<1_000).map { index in
            makeItem(title: "Item \(index)", timestamp: TimeInterval(index))
        }
        items.forEach(context.insert)
        try context.save()

        let state = ViewerState()
        var itemIDsAtPresentation: [PersistentIdentifier] = []
        let controller = ViewerPanelController(
            modelContainer: container,
            viewerState: state,
            onClearHistory: {},
            reportLoadFailure: { error in
                XCTFail("Unexpected load failure: \(error)")
            },
            presentPanel: { _ in
                itemIDsAtPresentation = state.itemIDs
            }
        )

        XCTAssertTrue(controller.show())

        let expectedIDs = items.reversed().map(\.persistentModelID)
        XCTAssertEqual(itemIDsAtPresentation, expectedIDs)
        XCTAssertEqual(state.itemIDs, expectedIDs)
        XCTAssertEqual(state.selectedID, expectedIDs.first)
    }

    private struct ItemFixture {
        let container: ModelContainer
        let items: [ClipItem]
    }

    private func makeItemFixture(count: Int) throws -> ItemFixture {
        let container = try makeContainer()
        let context = ModelContext(container)
        let items = (0..<count).map { index in
            makeItem(title: "Item \(index)", timestamp: TimeInterval(index))
        }
        items.forEach(context.insert)
        try context.save()
        return ItemFixture(container: container, items: items)
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
}
