import AppKit
import SwiftData
import XCTest
@testable import Yank

@MainActor
final class SnippetEditorWindowControllerTests: XCTestCase {
    func testShowCreatesWindowOnceAndReusesIt() throws {
        let container = try makeContainer()
        var factoryCount = 0
        var presentedWindows: [NSWindow] = []
        let controller = SnippetEditorWindowController(
            modelContainer: container,
            windowFactory: { contentView in
                factoryCount += 1
                let window = NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: false)
                window.contentView = contentView
                return window
            },
            windowPresenter: { presentedWindows.append($0) }
        )

        XCTAssertTrue(controller.show())
        XCTAssertTrue(controller.show())

        XCTAssertEqual(factoryCount, 1)
        XCTAssertEqual(presentedWindows.count, 2)
        XCTAssertTrue(presentedWindows[0] === presentedWindows[1])
    }

    func testWindowShouldCloseAllowsCleanStateWithoutPrompt() throws {
        let container = try makeContainer()
        var promptCount = 0
        let controller = SnippetEditorWindowController(
            modelContainer: container,
            dirtyDraftPrompt: {
                promptCount += 1
                return .cancel
            }
        )

        XCTAssertTrue(controller.windowShouldClose(NSWindow()))
        XCTAssertEqual(promptCount, 0)
    }

    func testWindowShouldCloseCancelPreservesDirtyDraft() throws {
        let fixture = try makeSnippetFixture()
        let state = SnippetEditorState()
        state.selectSnippet(fixture.snippet)
        state.draft?.content = "Changed"
        let controller = SnippetEditorWindowController(
            modelContainer: fixture.container,
            state: state,
            dirtyDraftPrompt: { .cancel }
        )

        XCTAssertFalse(controller.windowShouldClose(NSWindow()))
        XCTAssertEqual(state.draft?.content, "Changed")
        XCTAssertTrue(state.hasDirtyDraft)
    }

    func testWindowShouldCloseSaveFailureReportsAndStaysOpen() throws {
        let fixture = try makeSnippetFixture()
        let state = SnippetEditorState()
        state.selectSnippet(fixture.snippet)
        state.draft?.content = "Changed"
        fixture.container.mainContext.insert(SnippetFolder(title: "Pending", sortOrder: 1))
        var reportedOperation: String?
        let controller = SnippetEditorWindowController(
            modelContainer: fixture.container,
            state: state,
            dirtyDraftPrompt: { .save },
            errorReporter: { operation, _ in reportedOperation = operation }
        )

        XCTAssertFalse(controller.windowShouldClose(NSWindow()))
        XCTAssertEqual(reportedOperation, "save the snippet")
        XCTAssertEqual(state.draft?.content, "Changed")
        XCTAssertTrue(state.hasDirtyDraft)
        fixture.container.mainContext.rollback()
    }

    private struct SnippetFixture {
        let container: ModelContainer
        let snippet: Snippet
    }

    func testPerformClipyXMLImportUsesPickerAndUpdatesSelection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = SnippetFolder(title: "Existing", sortOrder: 0)
        context.insert(existing)
        try context.save()

        let state = SnippetEditorState()
        state.selectFolder(existing)
        let url = try writeTempXML(
            """
            <folders>
              <folder>
                <title>Imported</title>
                <snippets>
                  <snippet>
                    <title>First</title>
                    <content>hello</content>
                  </snippet>
                </snippets>
              </folder>
            </folders>
            """
        )
        defer { try? FileManager.default.removeItem(at: url) }
        var pickerCount = 0

        XCTAssertTrue(SnippetEditorWindowController.performClipyXMLImport(
            using: {
                pickerCount += 1
                return url
            },
            state: state,
            context: context,
            errorReporter: { operation, error in
                XCTFail("Unexpected \(operation) error: \(error)")
            }
        ))

        XCTAssertEqual(pickerCount, 1)
        let folders = try context.fetch(FetchDescriptor<SnippetFolder>())
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(folders.map(\.title), ["Existing", "Imported"])
        XCTAssertEqual(state.selectedFolderID, folders[1].persistentModelID)
        let snippets = SnippetOrdering.snippets(folders[1].snippets)
        XCTAssertEqual(snippets.map(\.title), ["First"])
        XCTAssertEqual(state.selectedSnippetID, snippets[0].persistentModelID)
    }

    func testPerformClipyXMLImportCancellationIsNoOp() throws {
        let fixture = try makeSnippetFixture()
        let state = SnippetEditorState()
        state.selectSnippet(fixture.snippet)
        let selectedFolderID = state.selectedFolderID
        let selectedSnippetID = state.selectedSnippetID
        var pickerCount = 0
        var reportedError = false

        XCTAssertFalse(SnippetEditorWindowController.performClipyXMLImport(
            using: {
                pickerCount += 1
                return nil
            },
            state: state,
            context: fixture.container.mainContext,
            errorReporter: { _, _ in reportedError = true }
        ))

        XCTAssertEqual(pickerCount, 1)
        XCTAssertFalse(reportedError)
        XCTAssertEqual(state.selectedFolderID, selectedFolderID)
        XCTAssertEqual(state.selectedSnippetID, selectedSnippetID)
        XCTAssertEqual(
            try fixture.container.mainContext.fetch(FetchDescriptor<SnippetFolder>()).count,
            1
        )
    }

    func testPerformClipyXMLImportReadFailureReportsUnderlyingErrorAndPreservesState() throws {
        let fixture = try makeSnippetFixture()
        let state = SnippetEditorState()
        state.selectSnippet(fixture.snippet)
        let selectedFolderID = state.selectedFolderID
        let selectedSnippetID = state.selectedSnippetID
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-yank-clipy-\(UUID().uuidString).xml")
        var reportedOperation: String?
        var reportedError: Error?

        XCTAssertFalse(SnippetEditorWindowController.performClipyXMLImport(
            using: { missingURL },
            state: state,
            context: fixture.container.mainContext,
            errorReporter: { operation, error in
                reportedOperation = operation
                reportedError = error
            }
        ))

        XCTAssertEqual(reportedOperation, "import snippets")
        let readError = try XCTUnwrap(reportedError as? ClipySnippetFileReadError)
        XCTAssertEqual(readError.fileName, missingURL.lastPathComponent)
        let underlyingError = readError.underlyingError as NSError
        XCTAssertEqual(underlyingError.domain, NSCocoaErrorDomain)
        XCTAssertEqual(underlyingError.code, NSFileReadNoSuchFileError)
        XCTAssertEqual(state.selectedFolderID, selectedFolderID)
        XCTAssertEqual(state.selectedSnippetID, selectedSnippetID)
        XCTAssertEqual(
            try fixture.container.mainContext.fetch(FetchDescriptor<SnippetFolder>()).count,
            1
        )
    }

    func testImportClipyXMLInvalidLeavesExistingDataUnchanged() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = SnippetFolder(title: "Existing", sortOrder: 0)
        let snippet = Snippet(title: "Keep", content: "body", sortOrder: 0, folder: existing)
        context.insert(existing)
        context.insert(snippet)
        try context.save()

        let state = SnippetEditorState()
        state.selectSnippet(snippet)
        let selectedFolderID = state.selectedFolderID
        let selectedSnippetID = state.selectedSnippetID

        let url = try writeTempXML("<folders><folder><index>1</index></folder></folders>")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try SnippetEditorWindowController.importClipyXML(
            from: url,
            state: state,
            context: context
        )) { error in
            XCTAssertEqual(
                error as? ClipySnippetXMLParserError,
                .unexpectedElement(path: "folders/folder/index")
            )
        }

        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SnippetFolder>()).map(\.title), ["Existing"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<Snippet>()).map(\.title), ["Keep"])
        XCTAssertEqual(state.selectedFolderID, selectedFolderID)
        XCTAssertEqual(state.selectedSnippetID, selectedSnippetID)
    }

    func testImportClipyXMLEmptyFileKeepsSelection() throws {
        let fixture = try makeSnippetFixture()
        let state = SnippetEditorState()
        state.selectSnippet(fixture.snippet)
        let selectedFolderID = state.selectedFolderID
        let selectedSnippetID = state.selectedSnippetID

        let url = try writeTempXML("<folders/>")
        defer { try? FileManager.default.removeItem(at: url) }

        try SnippetEditorWindowController.importClipyXML(
            from: url,
            state: state,
            context: fixture.container.mainContext
        )

        XCTAssertEqual(state.selectedFolderID, selectedFolderID)
        XCTAssertEqual(state.selectedSnippetID, selectedSnippetID)
        XCTAssertEqual(
            try fixture.container.mainContext.fetch(FetchDescriptor<SnippetFolder>()).count,
            1
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSnippetFixture() throws -> SnippetFixture {
        let container = try makeContainer()
        let context = container.mainContext
        let folder = SnippetFolder(title: "Folder", sortOrder: 0)
        let snippet = Snippet(title: "Snippet", content: "Content", sortOrder: 0, folder: folder)
        context.insert(folder)
        context.insert(snippet)
        try context.save()
        return SnippetFixture(container: container, snippet: snippet)
    }

    private func writeTempXML(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("yank-clipy-import-\(UUID().uuidString).xml")
        try Data(contents.utf8).write(to: url)
        return url
    }
}
