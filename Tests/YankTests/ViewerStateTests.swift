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

    // MARK: - Tab switching

    func testInitialTab_isHistory() {
        XCTAssertEqual(state.selectedTab, .history)
    }

    func testSwitchTabForward_fromHistory_selectsSnippets() {
        state.perform(.switchTab(.forward))

        XCTAssertEqual(state.selectedTab, .snippets)
    }

    func testSwitchTabForward_fromSnippets_staysAtSnippets() {
        state.selectedTab = .snippets

        state.perform(.switchTab(.forward))

        XCTAssertEqual(state.selectedTab, .snippets)
    }

    func testSwitchTabBackward_fromSnippets_selectsHistory() {
        state.selectedTab = .snippets

        state.perform(.switchTab(.backward))

        XCTAssertEqual(state.selectedTab, .history)
    }

    func testSwitchTabBackward_fromHistory_staysAtHistory() {
        state.perform(.switchTab(.backward))

        XCTAssertEqual(state.selectedTab, .history)
    }

    func testHistoryOnlyViewActions_areIgnoredInSnippets() {
        state.selectedTab = .snippets

        state.perform(.deleteSelected)
        state.perform(.clearHistory)

        XCTAssertNil(state.pendingAction)
    }

    func testPaste_isAvailableInSnippets() {
        state.selectedTab = .snippets

        state.perform(.paste(.original))

        XCTAssertEqual(state.pendingAction, .paste(.original))
    }

    func testClose_isAvailableInSnippets() {
        state.selectedTab = .snippets

        state.perform(.close)

        XCTAssertEqual(state.pendingAction, .close)
    }

    // MARK: - move(.down)

    func testMoveDown_fromFirst_selectsSecond() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[0]

        state.perform(.move(.down))

        XCTAssertEqual(state.selectedHistoryID, ids[1])
    }

    func testMoveDown_fromLast_staysAtLast() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[2]

        state.perform(.move(.down))

        XCTAssertEqual(state.selectedHistoryID, ids[2])
    }

    func testMoveDown_noSelection_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = nil

        state.perform(.move(.down))

        XCTAssertEqual(state.selectedHistoryID, ids[0])
    }

    // MARK: - move(.up)

    func testMoveUp_fromSecond_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[1]

        state.perform(.move(.up))

        XCTAssertEqual(state.selectedHistoryID, ids[0])
    }

    func testMoveUp_fromFirst_staysAtFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[0]

        state.perform(.move(.up))

        XCTAssertEqual(state.selectedHistoryID, ids[0])
    }

    func testMoveUp_noSelection_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = nil

        state.perform(.move(.up))

        XCTAssertEqual(state.selectedHistoryID, ids[0])
    }

    func testMoveUp_emptyItems_doesNothing() {
        state.replaceHistoryItems(with: [])
        state.selectedHistoryID = nil

        state.perform(.move(.up))

        XCTAssertNil(state.selectedHistoryID)
    }

    // MARK: - jumpToStart / jumpToEnd

    func testJumpToStart_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[2]

        state.perform(.jumpToStart)

        XCTAssertEqual(state.selectedHistoryID, ids[0])
    }

    func testJumpToEnd_selectsLast() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[0]

        state.perform(.jumpToEnd)

        XCTAssertEqual(state.selectedHistoryID, ids[2])
    }

    // MARK: - pendingAction routing

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
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[1]

        state.removeHistoryItem(id: ids[1])

        XCTAssertEqual(state.historyItemIDs, [ids[0], ids[2]])
        XCTAssertEqual(state.selectedHistoryID, ids[2])
    }

    func testRemoveItem_fromLast_selectsPreviousItem() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[2]

        state.removeHistoryItem(id: ids[2])

        XCTAssertEqual(state.historyItemIDs, [ids[0], ids[1]])
        XCTAssertEqual(state.selectedHistoryID, ids[1])
    }

    func testRemoveItem_onlyItem_clearsSelection() throws {
        let ids = try makeItemIDs(count: 1)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[0]

        state.removeHistoryItem(id: ids[0])

        XCTAssertEqual(state.historyItemIDs, [])
        XCTAssertNil(state.selectedHistoryID)
    }

    func testReplaceItems_whenSelectionWasDeleted_selectsFirst() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[1]

        state.replaceHistoryItems(with: [ids[0], ids[2]])

        XCTAssertEqual(state.historyItemIDs, [ids[0], ids[2]])
        XCTAssertEqual(state.selectedHistoryID, ids[0])
    }

    func testReplaceItems_whenSelectionStillPresent_keepsSelection() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[1]

        // A newer item is prepended (newest-first) while the current
        // selection is still present; selection must not jump to the top.
        let newID = try makeItemIDs(count: 1)[0]
        state.replaceHistoryItems(with: [newID] + ids)

        XCTAssertEqual(state.historyItemIDs, [newID] + ids)
        XCTAssertEqual(state.selectedHistoryID, ids[1])
    }

    // MARK: - Edge cases

    func testMoveDown_emptyItems_doesNothing() {
        state.replaceHistoryItems(with: [])
        state.selectedHistoryID = nil

        state.perform(.move(.down))

        XCTAssertNil(state.selectedHistoryID)
    }

    func testJumpToStart_emptyItems_setsNil() {
        state.replaceHistoryItems(with: [])

        state.perform(.jumpToStart)

        XCTAssertNil(state.selectedHistoryID)
    }

    func testJumpToEnd_emptyItems_setsNil() {
        state.replaceHistoryItems(with: [])

        state.perform(.jumpToEnd)

        XCTAssertNil(state.selectedHistoryID)
    }

    // MARK: - Key repeat simulation (Issue #6 core test)

    func testRapidMoveDown_advancesEveryStep() throws {
        let ids = try makeItemIDs(count: 5)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[0]

        for _ in 0..<4 {
            state.perform(.move(.down))
        }

        XCTAssertEqual(state.selectedHistoryID, ids[4])
    }

    func testRapidMoveDown_clampedAtEnd() throws {
        let ids = try makeItemIDs(count: 3)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[0]

        for _ in 0..<10 {
            state.perform(.move(.down))
        }

        XCTAssertEqual(state.selectedHistoryID, ids[2])
    }

    func testRapidMoveUp_advancesEveryStep() throws {
        let ids = try makeItemIDs(count: 5)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[4]

        for _ in 0..<4 {
            state.perform(.move(.up))
        }

        XCTAssertEqual(state.selectedHistoryID, ids[0])
    }

    func testOneHundredMovesInLargeHistory_advancesOneHundredRows() throws {
        let ids = try makeItemIDs(count: 1_000)
        state.replaceHistoryItems(with: ids)
        state.selectedHistoryID = ids[0]

        for _ in 0..<100 {
            state.perform(.move(.down))
        }

        XCTAssertEqual(state.selectedHistoryID, ids[100])
    }
}
