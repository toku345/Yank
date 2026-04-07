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

    private func makeItemIDs(count: Int) throws -> [PersistentIdentifier] {
        try (0..<count).map { i in
            let item = ClipItem(
                title: "Item \(i)",
                primaryType: "public.utf8-plain-text",
                availableTypes: ["public.utf8-plain-text"],
                stringValue: "content \(i)"
            )
            context.insert(item)
            try context.save()
            return item.persistentModelID
        }
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
        state.perform(.paste)

        XCTAssertEqual(state.pendingAction, .paste)
    }

    func testClose_setsPendingAction() {
        state.perform(.close)

        XCTAssertEqual(state.pendingAction, .close)
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
