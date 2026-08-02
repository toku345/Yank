import SwiftData
import XCTest
@testable import Yank

@MainActor
final class SnippetEditorStateTests: XCTestCase {
    private enum TestError: Error {
        case saveFailed
    }

    func testSaveNewDraftCreatesSnippetAndSelectsIt() throws {
        let fixture = try makeFixture()
        let state = SnippetEditorState()
        state.selectFolder(fixture.folder)
        state.beginNewSnippet(in: fixture.folder)
        state.draft?.title = "  Greeting  "
        state.draft?.content = "Hello"

        try state.saveDraft(in: fixture.context)

        let snippet = try XCTUnwrap(fixture.context.fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertEqual(snippet.title, "Greeting")
        XCTAssertEqual(snippet.content, "Hello")
        XCTAssertEqual(state.selectedSnippetID, snippet.persistentModelID)
        XCTAssertFalse(state.hasDirtyDraft)
    }

    func testDiscardNewDraftRestoresPreviousSelection() throws {
        let fixture = try makeFixture(snippetTitle: "Existing")
        let snippet = try XCTUnwrap(fixture.snippet)
        let state = SnippetEditorState()
        state.selectSnippet(snippet)
        state.beginNewSnippet(in: fixture.folder)
        state.draft?.title = "Unsaved"

        try state.discardDraft(in: fixture.context)

        XCTAssertEqual(state.selectedSnippetID, snippet.persistentModelID)
        XCTAssertEqual(state.draft?.title, "Existing")
        XCTAssertFalse(state.hasDirtyDraft)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Snippet>()), 1)
    }

    func testCancelDirtyResolutionPreservesDraft() throws {
        let fixture = try makeFixture(snippetTitle: "Existing")
        let snippet = try XCTUnwrap(fixture.snippet)
        let state = SnippetEditorState()
        state.selectSnippet(snippet)
        state.draft?.content = "Changed"

        let resolved = try state.resolveDirtyDraft(
            decisionProvider: { .cancel },
            in: fixture.context
        )

        XCTAssertFalse(resolved)
        XCTAssertEqual(state.draft?.content, "Changed")
        XCTAssertTrue(state.hasDirtyDraft)
        XCTAssertEqual(snippet.content, "Existing")
    }

    func testSaveFailurePreservesDirtyDraftAndRollsBackModel() throws {
        let fixture = try makeFixture(snippetTitle: "Existing")
        let snippet = try XCTUnwrap(fixture.snippet)
        let state = SnippetEditorState()
        state.selectSnippet(snippet)
        state.draft?.title = "Changed"

        XCTAssertThrowsError(try state.saveDraft(
            in: fixture.context,
            saveChanges: { _ in throw TestError.saveFailed }
        ))

        XCTAssertEqual(snippet.title, "Existing")
        XCTAssertEqual(state.draft?.title, "Changed")
        XCTAssertTrue(state.hasDirtyDraft)
        XCTAssertFalse(fixture.context.hasChanges)
    }

    func testSynchronizeRepairsMissingFolderAndSelectsFirstSnippet() throws {
        let fixture = try makeFixture()
        let otherFolder = SnippetFolder(title: "Other", sortOrder: 1)
        let otherSnippet = Snippet(
            title: "Other Snippet",
            content: "content",
            sortOrder: 0,
            folder: otherFolder
        )
        fixture.context.insert(otherFolder)
        fixture.context.insert(otherSnippet)
        try fixture.context.save()
        let state = SnippetEditorState()
        state.selectedFolderID = fixture.folder.persistentModelID
        fixture.context.delete(fixture.folder)
        try fixture.context.save()

        state.synchronize(with: [otherFolder])

        XCTAssertEqual(state.selectedFolderID, otherFolder.persistentModelID)
        XCTAssertEqual(state.selectedSnippetID, otherSnippet.persistentModelID)
        XCTAssertEqual(state.draft?.title, "Other Snippet")
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let folder: SnippetFolder
        let snippet: Snippet?
    }

    private func makeFixture(snippetTitle: String? = nil) throws -> Fixture {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let folder = SnippetFolder(title: "Folder", sortOrder: 0)
        context.insert(folder)
        let snippet = snippetTitle.map {
            Snippet(title: $0, content: $0, sortOrder: 0, folder: folder)
        }
        if let snippet {
            context.insert(snippet)
        }
        try context.save()
        return Fixture(container: container, context: context, folder: folder, snippet: snippet)
    }
}
