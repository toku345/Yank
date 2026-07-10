import XCTest
import SwiftData
@testable import Yank

@MainActor
final class HistoryDeletionTests: XCTestCase {
    private var context: ModelContext!
    private var state: ViewerState!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ClipItem.self, configurations: config)
        context = ModelContext(container)
        state = ViewerState()
    }

    func testDeleteSelectedItem_deletesSwiftDataRowAndSelectsNext() throws {
        let items = try makeItems(count: 3)
        let ids = items.map(\.persistentModelID)
        state.itemIDs = ids
        state.selectedID = ids[1]

        let result = try HistoryDeletion.deleteSelectedItem(
            from: items,
            in: context,
            viewerState: state
        )

        let fetched = try context.fetch(FetchDescriptor<ClipItem>())
        XCTAssertEqual(result, .deleted)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertFalse(fetched.map(\.persistentModelID).contains(ids[1]))
        XCTAssertEqual(state.selectedID, ids[2])
    }

    func testDeleteSelectedItem_withoutSelectionDeletesNothingAndRepairsSelection() throws {
        let items = try makeItems(count: 2)
        let ids = items.map(\.persistentModelID)
        state.itemIDs = []
        state.selectedID = nil

        let result = try HistoryDeletion.deleteSelectedItem(
            from: items,
            in: context,
            viewerState: state
        )

        let fetched = try context.fetch(FetchDescriptor<ClipItem>())
        XCTAssertEqual(result, .noSelection)
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(state.itemIDs, ids)
        XCTAssertEqual(state.selectedID, ids[0])
    }

    func testDeleteSelectedItem_whenSelectionIsStaleDeletesNothingAndRepairsSelection() throws {
        let staleItem = try makeItems(count: 1)[0]
        let items = try makeItems(count: 2)
        let ids = items.map(\.persistentModelID)
        state.itemIDs = [staleItem.persistentModelID] + ids
        state.selectedID = staleItem.persistentModelID

        let result = try HistoryDeletion.deleteSelectedItem(
            from: items,
            in: context,
            viewerState: state
        )

        let fetched = try context.fetch(FetchDescriptor<ClipItem>())
        XCTAssertEqual(result, .selectedItemMissing(staleItem.persistentModelID))
        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(state.itemIDs, ids)
        XCTAssertEqual(state.selectedID, ids[0])
    }

    func testDeleteSelectedItem_whenSaveFailsRollsBackAndKeepsSelection() throws {
        let items = try makeItems(count: 2)
        let ids = items.map(\.persistentModelID)
        state.itemIDs = ids
        state.selectedID = ids[0]

        XCTAssertThrowsError(
            try HistoryDeletion.deleteSelectedItem(
                from: items,
                in: context,
                viewerState: state,
                saveChanges: { _ in throw TestSaveError.failure }
            )
        )

        let fetched = try context.fetch(FetchDescriptor<ClipItem>())
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(state.itemIDs, ids)
        XCTAssertEqual(state.selectedID, ids[0])
    }

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

    enum TestSaveError: Error {
        case failure
    }
}
