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
}
