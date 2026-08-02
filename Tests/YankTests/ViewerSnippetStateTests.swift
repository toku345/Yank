import SwiftData
import XCTest
@testable import Yank

@MainActor
final class ViewerSnippetStateTests: XCTestCase {
    private var context: ModelContext!
    private var state: ViewerState!

    override func setUpWithError() throws {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        state = ViewerState()
    }

    func testSwitchTabRoundTripPreservesBothSelections() throws {
        let historyIDs = try makeHistoryIDs(count: 2)
        let snippetIDs = try makeSnippetIDs(count: 2)
        state.historyItemIDs = historyIDs
        state.selectedHistoryID = historyIDs[1]
        state.snippetIDs = snippetIDs
        state.selectedSnippetID = snippetIDs[1]

        state.perform(.switchTab(.forward))
        state.perform(.switchTab(.backward))

        XCTAssertEqual(state.historyItemIDs, historyIDs)
        XCTAssertEqual(state.selectedHistoryID, historyIDs[1])
        XCTAssertEqual(state.snippetIDs, snippetIDs)
        XCTAssertEqual(state.selectedSnippetID, snippetIDs[1])
    }

    func testSnippetMovementUpdatesSnippetSelectionOnly() throws {
        let historyIDs = try makeHistoryIDs(count: 3)
        let snippetIDs = try makeSnippetIDs(count: 3)
        state.historyItemIDs = historyIDs
        state.selectedHistoryID = historyIDs[1]
        state.replaceSnippets(with: snippetIDs)
        state.selectedTab = .snippets

        state.perform(.move(.down))

        XCTAssertEqual(state.selectedSnippetID, snippetIDs[1])
        XCTAssertEqual(state.selectedHistoryID, historyIDs[1])
    }

    func testSnippetJumpActionsUseFirstAndLastSelectableSnippet() throws {
        let snippetIDs = try makeSnippetIDs(count: 3)
        state.replaceSnippets(with: snippetIDs)
        state.selectedTab = .snippets

        state.perform(.jumpToEnd)
        XCTAssertEqual(state.selectedSnippetID, snippetIDs[2])

        state.perform(.jumpToStart)
        XCTAssertEqual(state.selectedSnippetID, snippetIDs[0])
    }

    func testSnippetMovementClampsAtCollectionBoundaries() throws {
        let snippetIDs = try makeSnippetIDs(count: 2)
        state.replaceSnippets(with: snippetIDs)
        state.selectedTab = .snippets

        state.perform(.move(.up))
        XCTAssertEqual(state.selectedSnippetID, snippetIDs[0])

        state.selectedSnippetID = snippetIDs[1]
        state.perform(.move(.down))
        XCTAssertEqual(state.selectedSnippetID, snippetIDs[1])
    }

    func testReplaceSnippetsSelectsFirstAndPreservesValidSelection() throws {
        let snippetIDs = try makeSnippetIDs(count: 3)

        state.replaceSnippets(with: snippetIDs)
        XCTAssertEqual(state.selectedSnippetID, snippetIDs[0])

        state.selectedSnippetID = snippetIDs[1]
        state.replaceSnippets(with: [snippetIDs[2], snippetIDs[1], snippetIDs[0]])

        XCTAssertEqual(state.selectedSnippetID, snippetIDs[1])
    }

    func testReplaceSnippetsMissingSelectionFallsBackToFirst() throws {
        let snippetIDs = try makeSnippetIDs(count: 3)
        state.replaceSnippets(with: snippetIDs)
        state.selectedSnippetID = snippetIDs[1]

        state.replaceSnippets(with: [snippetIDs[2], snippetIDs[0]])

        XCTAssertEqual(state.selectedSnippetID, snippetIDs[2])
    }

    func testReplaceSnippetsEmptyClearsSelection() throws {
        let snippetIDs = try makeSnippetIDs(count: 1)
        state.replaceSnippets(with: snippetIDs)

        state.replaceSnippets(with: [])

        XCTAssertTrue(state.snippetIDs.isEmpty)
        XCTAssertNil(state.selectedSnippetID)
    }

    private func makeHistoryIDs(count: Int) throws -> [PersistentIdentifier] {
        let items = (0..<count).map { index in
            let item = ClipItem(
                title: "History \(index)",
                primaryType: "public.utf8-plain-text",
                availableTypes: ["public.utf8-plain-text"],
                stringValue: "history \(index)"
            )
            context.insert(item)
            return item
        }
        try context.save()
        return items.map(\.persistentModelID)
    }

    private func makeSnippetIDs(count: Int) throws -> [PersistentIdentifier] {
        let folder = SnippetFolder(title: "Folder", sortOrder: 0)
        context.insert(folder)
        let snippets = (0..<count).map { index in
            let snippet = Snippet(
                title: "Snippet \(index)",
                content: "content \(index)",
                sortOrder: index,
                folder: folder
            )
            context.insert(snippet)
            return snippet
        }
        try context.save()
        return snippets.map(\.persistentModelID)
    }
}
