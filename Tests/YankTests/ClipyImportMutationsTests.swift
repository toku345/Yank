import SwiftData
import XCTest
@testable import Yank

@MainActor
final class ClipyImportMutationsTests: XCTestCase {
    private enum TestError: Error {
        case saveFailed
    }

    func testImportClipyFoldersPersistsNormalizedTitlesAndOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let imported = [
            ClipyImportedFolder(
                title: "  Shell  ",
                snippets: [
                    ClipyImportedSnippet(title: "  List  ", content: "  rg --files\n"),
                    ClipyImportedSnippet(title: "   ", content: "blank-title"),
                    ClipyImportedSnippet(title: "", content: "missing-title")
                ]
            ),
            ClipyImportedFolder(
                title: "\n",
                snippets: []
            )
        ]

        let result = try SnippetMutations.importClipyFolders(imported, in: context)

        let readContext = ModelContext(container)
        let folders = try fetchFolders(from: readContext)
        XCTAssertEqual(folders.map(\.title), ["Shell", "untitled folder"])
        XCTAssertEqual(folders.map(\.sortOrder), [0, 1])
        let firstSnippets = try fetchSnippets(from: readContext, folderID: folders[0].persistentModelID)
        XCTAssertEqual(firstSnippets.map(\.title), ["List", "untitled snippet", "untitled snippet"])
        XCTAssertEqual(firstSnippets.map(\.content), ["  rg --files\n", "blank-title", "missing-title"])
        XCTAssertEqual(firstSnippets.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(result.selectedFolderID, folders[0].persistentModelID)
        XCTAssertEqual(result.selectedSnippetID, firstSnippets[0].persistentModelID)
        XCTAssertTrue(try fetchSnippets(from: readContext, folderID: folders[1].persistentModelID).isEmpty)
    }

    func testImportClipyFoldersAppendsAfterExistingFolders() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = try createFolder(title: "Existing", sortOrder: 0, in: context)
        let existingSnippet = try createSnippet(
            title: "Keep",
            sortOrder: 0,
            folder: existing,
            in: context
        )

        let result = try SnippetMutations.importClipyFolders(
            [
                ClipyImportedFolder(
                    title: "Imported",
                    snippets: [ClipyImportedSnippet(title: "New", content: "body")]
                )
            ],
            in: context
        )

        let readContext = ModelContext(container)
        let folders = try fetchFolders(from: readContext)
        XCTAssertEqual(folders.map(\.title), ["Existing", "Imported"])
        XCTAssertEqual(folders.map(\.sortOrder), [0, 1])
        let kept = try fetchSnippets(from: readContext, folderID: folders[0].persistentModelID)
        XCTAssertEqual(kept.map(\.title), ["Keep"])
        XCTAssertEqual(kept.map(\.sortOrder), [0])
        XCTAssertEqual(kept[0].content, "Keep")
        let imported = try fetchSnippets(from: readContext, folderID: folders[1].persistentModelID)
        XCTAssertEqual(imported.map(\.title), ["New"])
        XCTAssertEqual(result.selectedFolderID, folders[1].persistentModelID)
        XCTAssertEqual(result.selectedSnippetID, imported[0].persistentModelID)
        XCTAssertNotEqual(result.selectedSnippetID, existingSnippet.persistentModelID)
    }

    func testImportClipyFoldersEmptyIsNoOpSuccess() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = try createFolder(title: "Existing", sortOrder: 0, in: context)

        let result = try SnippetMutations.importClipyFolders([], in: context)

        XCTAssertNil(result.selectedFolder)
        XCTAssertNil(result.selectedSnippet)
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try fetchFolders(from: ModelContext(container)).map(\.title), ["Existing"])
    }

    func testImportClipyFoldersFailsClosedWhenContextHasPendingChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(SnippetFolder(title: "Pending", sortOrder: 0))

        XCTAssertThrowsError(try SnippetMutations.importClipyFolders(
            [ClipyImportedFolder(title: "Imported", snippets: [])],
            in: context
        )) { error in
            XCTAssertEqual(error as? SnippetEditorMutationError, .contextHasPendingChanges)
        }

        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SnippetFolder>()).map(\.title), ["Pending"])
        context.rollback()
    }

    func testImportClipyFoldersSaveFailureRollsBackCompletely() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = try createFolder(title: "Existing", sortOrder: 0, in: context)
        _ = try createSnippet(title: "Keep", sortOrder: 0, folder: existing, in: context)

        XCTAssertThrowsError(try SnippetMutations.importClipyFolders(
            [
                ClipyImportedFolder(
                    title: "Imported",
                    snippets: [ClipyImportedSnippet(title: "New", content: "body")]
                )
            ],
            in: context,
            saveChanges: { _ in throw TestError.saveFailed }
        ))

        XCTAssertFalse(context.hasChanges)
        let sameContextFolders = try fetchFolders(from: context)
        XCTAssertEqual(sameContextFolders.map(\.title), ["Existing"])
        XCTAssertEqual(
            try fetchSnippets(from: context, folderID: sameContextFolders[0].persistentModelID).map(\.title),
            ["Keep"]
        )
        XCTAssertFalse(sameContextFolders.contains { $0.title == "Imported" })

        let readContext = ModelContext(container)
        let folders = try fetchFolders(from: readContext)
        XCTAssertEqual(folders.map(\.title), ["Existing"])
        XCTAssertEqual(
            try fetchSnippets(from: readContext, folderID: folders[0].persistentModelID).map(\.title),
            ["Keep"]
        )
        XCTAssertFalse(try readContext.fetch(FetchDescriptor<Snippet>()).contains { $0.title == "New" })
    }

    func testImportClipyFoldersSelectsFolderOnlyWhenFirstFolderHasNoSnippets() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let result = try SnippetMutations.importClipyFolders(
            [
                ClipyImportedFolder(title: "Empty", snippets: []),
                ClipyImportedFolder(
                    title: "With Snippet",
                    snippets: [ClipyImportedSnippet(title: "S", content: "c")]
                )
            ],
            in: context
        )

        let folders = try fetchFolders(from: ModelContext(container))
        XCTAssertEqual(result.selectedFolderID, folders[0].persistentModelID)
        XCTAssertNil(result.selectedSnippetID)
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
