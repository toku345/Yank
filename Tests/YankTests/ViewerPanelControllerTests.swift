import SwiftData
import XCTest
@testable import Yank

@MainActor
final class ViewerPanelControllerTests: XCTestCase {
    private enum TestFailure: Error {
        case loadFailed
    }

    private var retainedControllers: [ViewerPanelController] = []
    private var retainedPanels: [ViewerPanel] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        try resetSharedContainer()
    }

    override func tearDown() {
        for panel in retainedPanels {
            panel.contentView = nil
            panel.close()
        }
        retainedPanels.removeAll()
        retainedControllers.removeAll()
        super.tearDown()
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
        state.replaceHistoryItems(with: [staleID, olderID])
        state.selectedHistoryID = olderID
        var presentationCount = 0

        let controller = retain(ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            onSnippetPaste: { _ in },
            loadHistoryIDs: { loadedIDs },
            reportLoadFailure: { error in
                XCTFail("Unexpected load failure: \(error)")
            },
            presentPanel: { panel in
                self.retain(panel)
                presentationCount += 1
                XCTAssertEqual(state.historyItemIDs, loadedIDs)
                XCTAssertEqual(state.selectedHistoryID, newestID)
            }
        ))

        XCTAssertTrue(controller.show())
        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(state.historyItemIDs, loadedIDs)
        XCTAssertEqual(state.selectedHistoryID, newestID)
    }

    func testShow_preservesSnippetsTabAndResetsHistorySelection() throws {
        let fixture = try makeItemFixture(count: 2)
        let newestID = fixture.items[0].persistentModelID
        let olderID = fixture.items[1].persistentModelID
        let loadedIDs = [newestID, olderID]
        let state = ViewerState()
        state.selectedTab = .snippets
        state.replaceHistoryItems(with: loadedIDs)
        state.selectedHistoryID = olderID
        var presentationCount = 0

        let controller = retain(ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            onSnippetPaste: { _ in },
            loadHistoryIDs: { loadedIDs },
            reportLoadFailure: { error in
                XCTFail("Unexpected load failure: \(error)")
            },
            presentPanel: { panel in
                self.retain(panel)
                presentationCount += 1
            }
        ))

        XCTAssertTrue(controller.show())
        XCTAssertEqual(presentationCount, 1)
        XCTAssertEqual(state.selectedTab, .snippets)
        XCTAssertEqual(state.selectedHistoryID, newestID)
    }

    func testShow_emptySnapshotClearsStateAndPresentsEmptyViewer() throws {
        let fixture = try makeItemFixture(count: 1)
        let state = ViewerState()
        state.replaceHistoryItems(with: fixture.items.map(\.persistentModelID))
        state.selectedHistoryID = state.historyItemIDs.first
        var presentationCount = 0

        let controller = retain(ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            onSnippetPaste: { _ in },
            loadHistoryIDs: { [] },
            reportLoadFailure: { error in
                XCTFail("Unexpected load failure: \(error)")
            },
            presentPanel: { panel in
                self.retain(panel)
                presentationCount += 1
                XCTAssertTrue(state.historyItemIDs.isEmpty)
                XCTAssertNil(state.selectedHistoryID)
            }
        ))

        XCTAssertTrue(controller.show())
        XCTAssertEqual(presentationCount, 1)
        XCTAssertTrue(state.historyItemIDs.isEmpty)
        XCTAssertNil(state.selectedHistoryID)
    }

    func testShow_failureClearsStateBeforeReportingAndDoesNotPresent() throws {
        let fixture = try makeItemFixture(count: 1)
        let state = ViewerState()
        state.replaceHistoryItems(with: fixture.items.map(\.persistentModelID))
        state.selectedHistoryID = state.historyItemIDs.first
        var reportCount = 0
        var presentationCount = 0

        let controller = retain(ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            onSnippetPaste: { _ in },
            loadHistoryIDs: { throw TestFailure.loadFailed },
            reportLoadFailure: { error in
                reportCount += 1
                XCTAssertTrue(error is TestFailure)
                XCTAssertTrue(state.historyItemIDs.isEmpty)
                XCTAssertNil(state.selectedHistoryID)
            },
            presentPanel: { _ in presentationCount += 1 }
        ))

        XCTAssertFalse(controller.show())
        XCTAssertEqual(reportCount, 1)
        XCTAssertEqual(presentationCount, 0)
        XCTAssertTrue(state.historyItemIDs.isEmpty)
        XCTAssertNil(state.selectedHistoryID)
    }

    func testShow_failurePreservesSnippetsTabAndDoesNotPresent() throws {
        let fixture = try makeItemFixture(count: 1)
        let state = ViewerState()
        state.selectedTab = .snippets
        state.replaceHistoryItems(with: fixture.items.map(\.persistentModelID))
        state.selectedHistoryID = state.historyItemIDs.first
        var reportCount = 0
        var presentationCount = 0

        let controller = retain(ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            onSnippetPaste: { _ in },
            loadHistoryIDs: { throw TestFailure.loadFailed },
            reportLoadFailure: { _ in reportCount += 1 },
            presentPanel: { _ in presentationCount += 1 }
        ))

        XCTAssertFalse(controller.show())
        XCTAssertEqual(reportCount, 1)
        XCTAssertEqual(presentationCount, 0)
        XCTAssertEqual(state.selectedTab, .snippets)
        XCTAssertTrue(state.historyItemIDs.isEmpty)
        XCTAssertNil(state.selectedHistoryID)
    }

    func testShow_failureAfterSuccessDoesNotPresentExistingPanelAgain() throws {
        let fixture = try makeItemFixture(count: 2)
        let loadedIDs = fixture.items.map(\.persistentModelID)
        let state = ViewerState()
        var loadCount = 0
        var reportCount = 0
        var presentationCount = 0

        let controller = retain(ViewerPanelController(
            modelContainer: fixture.container,
            viewerState: state,
            onClearHistory: {},
            onSnippetPaste: { _ in },
            loadHistoryIDs: {
                loadCount += 1
                if loadCount == 1 {
                    return loadedIDs
                }
                throw TestFailure.loadFailed
            },
            reportLoadFailure: { _ in
                reportCount += 1
                XCTAssertTrue(state.historyItemIDs.isEmpty)
                XCTAssertNil(state.selectedHistoryID)
            },
            presentPanel: { panel in
                self.retain(panel)
                presentationCount += 1
            }
        ))

        XCTAssertTrue(controller.show())
        XCTAssertEqual(presentationCount, 1)

        XCTAssertFalse(controller.show())
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(reportCount, 1)
        XCTAssertEqual(presentationCount, 1)
        XCTAssertTrue(state.historyItemIDs.isEmpty)
        XCTAssertNil(state.selectedHistoryID)
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
        let controller = retain(ViewerPanelController(
            modelContainer: container,
            viewerState: state,
            onClearHistory: {},
            onSnippetPaste: { _ in },
            reportLoadFailure: { error in
                XCTFail("Unexpected load failure: \(error)")
            },
            presentPanel: { panel in
                self.retain(panel)
                itemIDsAtPresentation = state.historyItemIDs
            }
        ))

        XCTAssertTrue(controller.show())

        let expectedIDs = items.reversed().map(\.persistentModelID)
        XCTAssertEqual(itemIDsAtPresentation, expectedIDs)
        XCTAssertEqual(state.historyItemIDs, expectedIDs)
        XCTAssertEqual(state.selectedHistoryID, expectedIDs.first)
    }
}

extension ViewerPanelControllerTests {
    func testShow_forwardsSelectedSnippetPasteFromMountedView() async throws {
        let container = try makeIsolatedContainer()
        let context = container.mainContext
        let folder = SnippetFolder(title: "Folder", sortOrder: 0)
        let snippet = Snippet(
            title: "Greeting",
            content: "hello",
            sortOrder: 0,
            folder: folder
        )
        context.insert(folder)
        context.insert(snippet)
        try context.save()

        let state = ViewerState()
        state.selectedTab = .snippets
        let pasteExpectation = expectation(description: "controller forwarded snippet paste")
        var pastedIDs: [PersistentIdentifier] = []
        let controller = retain(ViewerPanelController(
            modelContainer: container,
            viewerState: state,
            onClearHistory: {},
            onSnippetPaste: { pastedSnippet in
                pastedIDs.append(pastedSnippet.persistentModelID)
                pasteExpectation.fulfill()
            },
            loadHistoryIDs: { [] },
            reportLoadFailure: { error in
                XCTFail("Unexpected load failure: \(error)")
            },
            presentPanel: { panel in
                self.retain(panel)
                panel.contentView?.layoutSubtreeIfNeeded()
            }
        ))

        XCTAssertTrue(controller.show())
        try await waitForSnippetIDs([snippet.persistentModelID], in: state)

        state.perform(.paste(.original))

        await fulfillment(of: [pasteExpectation], timeout: 1.0)
        XCTAssertEqual(pastedIDs, [snippet.persistentModelID])
    }
}

private extension ViewerPanelControllerTests {
    static let containerResult = Result<ModelContainer, Error> {
        let schema = YankSchema.current
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    struct ItemFixture {
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
        try Self.containerResult.get()
    }

    private func makeIsolatedContainer() throws -> ModelContainer {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func waitForSnippetIDs(
        _ expectedIDs: [PersistentIdentifier],
        in state: ViewerState
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(1)
        while state.snippetIDs != expectedIDs, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(state.snippetIDs, expectedIDs)
        XCTAssertEqual(state.selectedSnippetID, expectedIDs.first)
    }

    func resetSharedContainer() throws {
        let context = try Self.containerResult.get().mainContext
        for item in try context.fetch(FetchDescriptor<ClipItem>()) {
            context.delete(item)
        }
        try context.save()
    }

    private func retain(_ controller: ViewerPanelController) -> ViewerPanelController {
        retainedControllers.append(controller)
        return controller
    }

    func retain(_ panel: ViewerPanel) {
        retainedPanels.append(panel)
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
