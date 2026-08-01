import SwiftData
import XCTest
@testable import Yank

@MainActor
final class SnippetMutationsTests: XCTestCase {
    private enum TestError: Error {
        case saveFailed
    }

    func testCreateFolderAndSnippetPersistsNormalizedValues() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let folderResult = try SnippetMutations.createFolder(title: "  Shell  ", in: context)
        let folderID = try XCTUnwrap(folderResult.selectedFolderID)
        try SnippetMutations.createSnippet(
            title: "  List Files  ",
            content: "  rg --files\n",
            folderID: folderID,
            in: context
        )

        let readContext = ModelContext(container)
        let folder = try XCTUnwrap(readContext.fetch(FetchDescriptor<SnippetFolder>()).first)
        let snippet = try XCTUnwrap(readContext.fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertEqual(folder.title, "Shell")
        XCTAssertEqual(folder.sortOrder, 0)
        XCTAssertEqual(snippet.title, "List Files")
        XCTAssertEqual(snippet.content, "  rg --files\n")
        XCTAssertEqual(snippet.sortOrder, 0)
        XCTAssertEqual(snippet.folder?.persistentModelID, folder.persistentModelID)
    }

    func testCreateRejectsBlankTitleWithoutChangingStore() throws {
        let container = try makeContainer()
        let context = container.mainContext

        XCTAssertThrowsError(try SnippetMutations.createFolder(title: " \n ", in: context)) { error in
            XCTAssertTrue(error is SnippetEditorMutationError)
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SnippetFolder>()).isEmpty)
    }

    func testMutationFailsClosedWhenContextHasPendingChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pendingFolder = SnippetFolder(title: "Pending", sortOrder: 0)
        context.insert(pendingFolder)

        XCTAssertThrowsError(try SnippetMutations.createFolder(title: "Other", in: context)) { error in
            XCTAssertEqual(error as? SnippetEditorMutationError, .contextHasPendingChanges)
        }

        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SnippetFolder>()).map(\.title), ["Pending"])
        context.rollback()
    }

    func testMoveFolderNormalizesDenseOrderInFreshContext() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = try createFolder(title: "First", sortOrder: 4, in: context)
        let second = try createFolder(title: "Second", sortOrder: 4, in: context)
        let third = try createFolder(title: "Third", sortOrder: 9, in: context)

        XCTAssertTrue(try SnippetMutations.moveFolder(
            id: third.persistentModelID,
            before: first.persistentModelID,
            in: context
        ))

        let fetched = try fetchFolders(from: ModelContext(container))
        XCTAssertEqual(fetched.map(\.title), ["Third", "First", "Second"])
        XCTAssertEqual(fetched.map(\.sortOrder), [0, 1, 2])
    }

    func testMoveSnippetWithinFolderNormalizesDenseOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let folder = try createFolder(title: "Shell", sortOrder: 0, in: context)
        let first = try createSnippet(title: "First", sortOrder: 0, folder: folder, in: context)
        _ = try createSnippet(title: "Second", sortOrder: 4, folder: folder, in: context)
        let third = try createSnippet(title: "Third", sortOrder: 8, folder: folder, in: context)

        let result = try SnippetMutations.moveSnippet(
            id: third.persistentModelID,
            to: folder.persistentModelID,
            before: first.persistentModelID,
            in: context
        )

        XCTAssertEqual(result?.selectedSnippetID, third.persistentModelID)
        let snippets = try fetchSnippets(from: ModelContext(container), folderID: folder.persistentModelID)
        XCTAssertEqual(snippets.map(\.title), ["Third", "First", "Second"])
        XCTAssertEqual(snippets.map(\.sortOrder), [0, 1, 2])
    }

    func testMoveSnippetAcrossFoldersNormalizesBothFoldersAtomically() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let source = try createFolder(title: "Source", sortOrder: 0, in: context)
        let destination = try createFolder(title: "Destination", sortOrder: 1, in: context)
        let moved = try createSnippet(title: "Moved", sortOrder: 0, folder: source, in: context)
        _ = try createSnippet(title: "Remaining", sortOrder: 4, folder: source, in: context)
        _ = try createSnippet(title: "Existing", sortOrder: 3, folder: destination, in: context)

        let result = try SnippetMutations.moveSnippet(
            id: moved.persistentModelID,
            to: destination.persistentModelID,
            before: nil,
            in: context
        )

        XCTAssertEqual(result, SnippetMutationResult(
            selectedFolderID: destination.persistentModelID,
            selectedSnippetID: moved.persistentModelID
        ))
        let readContext = ModelContext(container)
        let sourceSnippets = try fetchSnippets(from: readContext, folderID: source.persistentModelID)
        let destinationSnippets = try fetchSnippets(from: readContext, folderID: destination.persistentModelID)
        XCTAssertEqual(sourceSnippets.map(\.title), ["Remaining"])
        XCTAssertEqual(sourceSnippets.map(\.sortOrder), [0])
        XCTAssertEqual(destinationSnippets.map(\.title), ["Existing", "Moved"])
        XCTAssertEqual(destinationSnippets.map(\.sortOrder), [0, 1])
    }

    func testDeleteSnippetSelectsNextAndPersistsDenseOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let folder = try createFolder(title: "Shell", sortOrder: 0, in: context)
        _ = try createSnippet(title: "First", sortOrder: 0, folder: folder, in: context)
        let second = try createSnippet(title: "Second", sortOrder: 1, folder: folder, in: context)
        let third = try createSnippet(title: "Third", sortOrder: 2, folder: folder, in: context)

        let result = try SnippetMutations.deleteSnippet(id: second.persistentModelID, in: context)

        XCTAssertEqual(result.selectedSnippetID, third.persistentModelID)
        let snippets = try fetchSnippets(from: ModelContext(container), folderID: folder.persistentModelID)
        XCTAssertEqual(snippets.map(\.title), ["First", "Third"])
        XCTAssertEqual(snippets.map(\.sortOrder), [0, 1])
    }

    func testSaveFailureRollsBackMovedSnippetAndOrdering() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let source = try createFolder(title: "Source", sortOrder: 0, in: context)
        let destination = try createFolder(title: "Destination", sortOrder: 1, in: context)
        let moved = try createSnippet(title: "Moved", sortOrder: 0, folder: source, in: context)

        XCTAssertThrowsError(try SnippetMutations.moveSnippet(
            id: moved.persistentModelID,
            to: destination.persistentModelID,
            before: nil,
            in: context,
            saveChanges: { _ in throw TestError.saveFailed }
        ))

        XCTAssertFalse(context.hasChanges)
        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertEqual(fetched.folder?.persistentModelID, source.persistentModelID)
        XCTAssertEqual(fetched.sortOrder, 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func createFolder(
        title: String,
        sortOrder: Int,
        in context: ModelContext
    ) throws -> SnippetFolder {
        let folder = SnippetFolder(title: title, sortOrder: sortOrder)
        context.insert(folder)
        try context.save()
        return folder
    }

    private func createSnippet(
        title: String,
        sortOrder: Int,
        folder: SnippetFolder,
        in context: ModelContext
    ) throws -> Snippet {
        let snippet = Snippet(title: title, content: title, sortOrder: sortOrder, folder: folder)
        context.insert(snippet)
        try context.save()
        return snippet
    }

    private func fetchFolders(from context: ModelContext) throws -> [SnippetFolder] {
        SnippetOrdering.folders(try context.fetch(FetchDescriptor<SnippetFolder>()))
    }

    private func fetchSnippets(
        from context: ModelContext,
        folderID: PersistentIdentifier
    ) throws -> [Snippet] {
        let snippets = try context.fetch(FetchDescriptor<Snippet>()).filter {
            $0.folder?.persistentModelID == folderID
        }
        return SnippetOrdering.snippets(snippets)
    }
}
