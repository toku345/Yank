import XCTest
import SwiftData
@testable import Yank

@MainActor
final class ViewerStateTests: XCTestCase {
    private var context: ModelContext!
    private var state: ViewerState!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ClipItem.self, configurations: config)
        context = ModelContext(container)
        state = ViewerState()
    }

    // MARK: - Helpers

    private func makeItems(count: Int) throws -> [ClipItem] {
        let items = (0..<count).map { i in
            let item = ClipItem(
                title: "Item \(i)",
                primaryType: "public.utf8-plain-text",
                availableTypes: ["public.utf8-plain-text"],
                stringValue: "content \(i)"
            )
            context.insert(item)
            return item
        }
        try context.save()
        return items
    }

    private func makeItemIDs(count: Int) throws -> [PersistentIdentifier] {
        try makeItems(count: count).map(\.persistentModelID)
    }

    // MARK: - move(.down)

    func testMoveDown_fromFirst_selectsSecond() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[0]

        state.perform(.move(.down))

        XCTAssertEqual(state.selectedID, ids[1])
    }

    func testMoveDown_fromLast_staysAtLast() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[2]

        state.perform(.move(.down))

        XCTAssertEqual(state.selectedID, ids[2])
    }

    func testMoveDown_noSelection_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = nil

        state.perform(.move(.down))

        XCTAssertEqual(state.selectedID, ids[0])
    }

    // MARK: - move(.up)

    func testMoveUp_fromSecond_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[1]

        state.perform(.move(.up))

        XCTAssertEqual(state.selectedID, ids[0])
    }

    func testMoveUp_fromFirst_staysAtFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[0]

        state.perform(.move(.up))

        XCTAssertEqual(state.selectedID, ids[0])
    }

    func testMoveUp_noSelection_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = nil

        state.perform(.move(.up))

        XCTAssertEqual(state.selectedID, ids[0])
    }

    func testMoveUp_emptyItems_doesNothing() {
        state.itemIDs = []
        state.selectedID = nil

        state.perform(.move(.up))

        XCTAssertNil(state.selectedID)
    }

    // MARK: - jumpToStart / jumpToEnd

    func testJumpToStart_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[2]

        state.perform(.jumpToStart)

        XCTAssertEqual(state.selectedID, ids[0])
    }

    func testJumpToEnd_selectsLast() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[0]

        state.perform(.jumpToEnd)

        XCTAssertEqual(state.selectedID, ids[2])
    }

    // MARK: - paste / close route to pendingAction

    func testPaste_setsPendingAction() {
        state.perform(.paste(.original))

        XCTAssertEqual(state.pendingAction, .paste(.original))
    }

    func testClose_setsPendingAction() {
        state.perform(.close)

        XCTAssertEqual(state.pendingAction, .close)
    }

    func testDeleteSelected_setsPendingAction() {
        state.perform(.deleteSelected)

        XCTAssertEqual(state.pendingAction, .deleteSelected)
    }

    func testClearHistory_setsPendingAction() {
        state.perform(.clearHistory)

        XCTAssertEqual(state.pendingAction, .clearHistory)
    }

    // MARK: - Deletion selection updates

    func testRemoveItem_fromMiddle_selectsNextItem() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[1]

        state.removeItem(id: ids[1])

        XCTAssertEqual(state.itemIDs, [ids[0], ids[2]])
        XCTAssertEqual(state.selectedID, ids[2])
    }

    func testRemoveItem_fromLast_selectsPreviousItem() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[2]

        state.removeItem(id: ids[2])

        XCTAssertEqual(state.itemIDs, [ids[0], ids[1]])
        XCTAssertEqual(state.selectedID, ids[1])
    }

    func testRemoveItem_onlyItem_clearsSelection() throws {
        let ids = try makeItemIDs(count: 1)
        state.itemIDs = ids
        state.selectedID = ids[0]

        state.removeItem(id: ids[0])

        XCTAssertEqual(state.itemIDs, [])
        XCTAssertNil(state.selectedID)
    }

    func testReplaceItems_whenSelectionWasDeleted_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[1]

        state.replaceItems(with: [ids[0], ids[2]])

        XCTAssertEqual(state.itemIDs, [ids[0], ids[2]])
        XCTAssertEqual(state.selectedID, ids[0])
    }

    // MARK: - SwiftData deletion actions

    func testDeleteSelectedItem_deletesSwiftDataRowAndSelectsNext() throws {
        let items = try makeItems(count: 3)
        let ids = items.map(\.persistentModelID)
        state.itemIDs = ids
        state.selectedID = ids[1]

        let didDelete = try HistoryDeletion.deleteSelectedItem(
            from: items,
            in: context,
            viewerState: state
        )

        let fetched = try context.fetch(FetchDescriptor<ClipItem>())
        XCTAssertTrue(didDelete)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertFalse(fetched.map(\.persistentModelID).contains(ids[1]))
        XCTAssertEqual(state.selectedID, ids[2])
    }

    func testClearAll_deletesAllSwiftDataRowsAndClearsSelection() throws {
        let items = try makeItems(count: 3)
        state.itemIDs = items.map(\.persistentModelID)
        state.selectedID = state.itemIDs.first

        try HistoryDeletion.clearAll(
            items: items,
            in: context,
            viewerState: state
        )

        let fetched = try context.fetch(FetchDescriptor<ClipItem>())
        XCTAssertEqual(fetched.count, 0)
        XCTAssertEqual(state.itemIDs, [])
        XCTAssertNil(state.selectedID)
    }

    // MARK: - Edge cases

    func testMoveDown_emptyItems_doesNothing() {
        state.itemIDs = []
        state.selectedID = nil

        state.perform(.move(.down))

        XCTAssertNil(state.selectedID)
    }

    func testJumpToStart_emptyItems_setsNil() {
        state.itemIDs = []

        state.perform(.jumpToStart)

        XCTAssertNil(state.selectedID)
    }

    func testJumpToEnd_emptyItems_setsNil() {
        state.itemIDs = []

        state.perform(.jumpToEnd)

        XCTAssertNil(state.selectedID)
    }

    // MARK: - Key repeat simulation (Issue #6 core test)

    func testRapidMoveDown_advancesEveryStep() throws {
        let ids = try makeItemIDs(count: 5)
        state.itemIDs = ids
        state.selectedID = ids[0]

        for _ in 0..<4 {
            state.perform(.move(.down))
        }

        XCTAssertEqual(state.selectedID, ids[4])
    }

    func testRapidMoveDown_clampedAtEnd() throws {
        let ids = try makeItemIDs(count: 3)
        state.itemIDs = ids
        state.selectedID = ids[0]

        for _ in 0..<10 {
            state.perform(.move(.down))
        }

        XCTAssertEqual(state.selectedID, ids[2])
    }

    func testRapidMoveUp_advancesEveryStep() throws {
        let ids = try makeItemIDs(count: 5)
        state.itemIDs = ids
        state.selectedID = ids[4]

        for _ in 0..<4 {
            state.perform(.move(.up))
        }

        XCTAssertEqual(state.selectedID, ids[0])
    }
}
