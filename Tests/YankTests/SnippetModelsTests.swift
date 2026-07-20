import SwiftData
import XCTest
@testable import Yank

final class SnippetModelsTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([SnippetFolder.self, Snippet.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testFolderAndSnippetRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let folder = SnippetFolder(title: "Shell", sortOrder: 0)
        let snippet = Snippet(
            title: "List files",
            content: "rg --files",
            sortOrder: 0,
            folder: folder
        )
        context.insert(folder)
        context.insert(snippet)
        try context.save()

        let fetchedFolder = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<SnippetFolder>()).first)
        XCTAssertEqual(fetchedFolder.title, "Shell")
        XCTAssertEqual(fetchedFolder.sortOrder, 0)
        XCTAssertEqual(fetchedFolder.snippets.map(\.title), ["List files"])

        let fetchedSnippet = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertEqual(fetchedSnippet.title, "List files")
        XCTAssertEqual(fetchedSnippet.content, "rg --files")
        XCTAssertEqual(fetchedSnippet.sortOrder, 0)
        XCTAssertEqual(fetchedSnippet.folder.persistentModelID, fetchedFolder.persistentModelID)
    }

    func testFoldersPersistSortOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(SnippetFolder(title: "Second", sortOrder: 1))
        context.insert(SnippetFolder(title: "First", sortOrder: 0))
        try context.save()

        let descriptor = FetchDescriptor<SnippetFolder>(
            sortBy: [SortDescriptor(\SnippetFolder.sortOrder)]
        )
        let folders = try ModelContext(container).fetch(descriptor)
        XCTAssertEqual(folders.map(\.title), ["First", "Second"])
    }

    func testSnippetsPersistSortOrderWithinFolder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let folder = SnippetFolder(title: "Shell", sortOrder: 0)
        context.insert(folder)
        context.insert(Snippet(title: "Second", content: "second", sortOrder: 1, folder: folder))
        context.insert(Snippet(title: "First", content: "first", sortOrder: 0, folder: folder))
        try context.save()

        let descriptor = FetchDescriptor<Snippet>(
            sortBy: [SortDescriptor(\Snippet.sortOrder)]
        )
        let snippets = try ModelContext(container).fetch(descriptor)
        XCTAssertEqual(snippets.map(\.title), ["First", "Second"])
        XCTAssertTrue(snippets.allSatisfy { $0.folder.persistentModelID == folder.persistentModelID })
    }

    func testDeletingFolderCascadesOnlyItsSnippets() throws {
        let container = try makeContainer()

        try autoreleasepool {
            let context = ModelContext(container)
            let deletedFolder = SnippetFolder(title: "Delete", sortOrder: 0)
            let retainedFolder = SnippetFolder(title: "Keep", sortOrder: 1)
            context.insert(deletedFolder)
            context.insert(retainedFolder)
            context.insert(Snippet(title: "Deleted", content: "deleted", sortOrder: 0, folder: deletedFolder))
            context.insert(Snippet(title: "Retained", content: "retained", sortOrder: 0, folder: retainedFolder))
            try context.save()
        }

        let deleteContext = ModelContext(container)
        let foldersBeforeDelete = try deleteContext.fetch(FetchDescriptor<SnippetFolder>(
            sortBy: [SortDescriptor(\SnippetFolder.sortOrder)]
        ))
        deleteContext.delete(try XCTUnwrap(foldersBeforeDelete.first))
        try deleteContext.save()

        let folders = try ModelContext(container).fetch(FetchDescriptor<SnippetFolder>())
        let snippets = try ModelContext(container).fetch(FetchDescriptor<Snippet>())
        XCTAssertEqual(folders.map(\.title), ["Keep"])
        XCTAssertEqual(snippets.map(\.title), ["Retained"])
    }
}
