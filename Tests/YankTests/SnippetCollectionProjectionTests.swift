import SwiftData
import XCTest
@testable import Yank

@MainActor
final class SnippetCollectionProjectionTests: XCTestCase {
    func testProjectionOrdersFoldersAndSnippetsAndSkipsEmptyFolderForSelection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let firstFolder = SnippetFolder(title: "First", sortOrder: 0)
        let emptyFolder = SnippetFolder(title: "Empty", sortOrder: 1)
        let lastFolder = SnippetFolder(title: "Last", sortOrder: 2)
        let firstSnippet = Snippet(
            title: "First snippet",
            content: "first",
            sortOrder: 0,
            folder: firstFolder
        )
        let secondSnippet = Snippet(
            title: "Second snippet",
            content: "second",
            sortOrder: 1,
            folder: firstFolder
        )
        let lastSnippet = Snippet(
            title: "Last snippet",
            content: "last",
            sortOrder: 0,
            folder: lastFolder
        )
        [lastFolder, emptyFolder, firstFolder].forEach(context.insert)
        [secondSnippet, lastSnippet, firstSnippet].forEach(context.insert)
        try context.save()

        let snapshots = SnippetCollectionProjection.snapshots(
            from: [lastFolder, emptyFolder, firstFolder]
        )

        XCTAssertEqual(snapshots.map(\.title), ["First", "Empty", "Last"])
        XCTAssertEqual(
            snapshots.map(\.snippetIDs),
            [
                [firstSnippet.persistentModelID, secondSnippet.persistentModelID],
                [],
                [lastSnippet.persistentModelID]
            ]
        )
        XCTAssertEqual(
            SnippetCollectionProjection.selectableSnippetIDs(from: snapshots),
            [
                firstSnippet.persistentModelID,
                secondSnippet.persistentModelID,
                lastSnippet.persistentModelID
            ]
        )
    }

    func testProjectionUsesPersistentIdentifierAsStableTieBreaker() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let firstFolder = SnippetFolder(title: "First", sortOrder: 0)
        let secondFolder = SnippetFolder(title: "Second", sortOrder: 0)
        context.insert(firstFolder)
        context.insert(secondFolder)
        try context.save()

        let snapshots = SnippetCollectionProjection.snapshots(
            from: [secondFolder, firstFolder]
        )
        let expectedIDs = [firstFolder, secondFolder]
            .map(\.persistentModelID)
            .sorted()

        XCTAssertEqual(snapshots.map(\.folderID), expectedIDs)
    }

    func testProjectedSelectionMovesAcrossFolderBoundaryWithoutChangingHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let firstFolder = SnippetFolder(title: "First", sortOrder: 0)
        let emptyFolder = SnippetFolder(title: "Empty", sortOrder: 1)
        let lastFolder = SnippetFolder(title: "Last", sortOrder: 2)
        let firstSnippet = Snippet(
            title: "First snippet",
            content: "first",
            sortOrder: 0,
            folder: firstFolder
        )
        let secondSnippet = Snippet(
            title: "Second snippet",
            content: "second",
            sortOrder: 1,
            folder: firstFolder
        )
        let lastSnippet = Snippet(
            title: "Last snippet",
            content: "last",
            sortOrder: 0,
            folder: lastFolder
        )
        let historyItem = ClipItem(
            title: "History",
            primaryType: "public.utf8-plain-text",
            availableTypes: ["public.utf8-plain-text"],
            stringValue: "history"
        )
        [firstFolder, emptyFolder, lastFolder].forEach(context.insert)
        [firstSnippet, secondSnippet, lastSnippet].forEach(context.insert)
        context.insert(historyItem)
        try context.save()
        let snapshots = SnippetCollectionProjection.snapshots(
            from: [lastFolder, firstFolder, emptyFolder]
        )
        let state = ViewerState()
        state.replaceHistoryItems(with: [historyItem.persistentModelID])
        state.replaceSnippets(
            with: SnippetCollectionProjection.selectableSnippetIDs(from: snapshots)
        )
        state.selectedSnippetID = secondSnippet.persistentModelID
        state.selectedTab = .snippets

        state.perform(.move(.down))

        XCTAssertEqual(state.selectedSnippetID, lastSnippet.persistentModelID)
        XCTAssertEqual(state.selectedHistoryID, historyItem.persistentModelID)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
