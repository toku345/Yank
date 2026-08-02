import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Yank

@MainActor
private final class ViewerSnippetLifecycleRecorder {
    private struct Snapshot: Equatable {
        let snippetIDs: [PersistentIdentifier]
        let selectedSnippetID: PersistentIdentifier?
    }

    private var observedSnapshots: [Snapshot] = []
    private var pendingExpectations: [(Snapshot, XCTestExpectation)] = []

    func record(
        snippetIDs: [PersistentIdentifier],
        selectedSnippetID: PersistentIdentifier?
    ) {
        let snapshot = Snapshot(
            snippetIDs: snippetIDs,
            selectedSnippetID: selectedSnippetID
        )
        observedSnapshots.append(snapshot)

        let matchingExpectations = pendingExpectations.filter { $0.0 == snapshot }
        pendingExpectations.removeAll { $0.0 == snapshot }
        matchingExpectations.forEach { $0.1.fulfill() }
    }

    func expect(
        snippetIDs: [PersistentIdentifier],
        selectedSnippetID: PersistentIdentifier?,
        expectation: XCTestExpectation
    ) {
        let snapshot = Snapshot(
            snippetIDs: snippetIDs,
            selectedSnippetID: selectedSnippetID
        )
        if observedSnapshots.contains(snapshot) {
            expectation.fulfill()
        } else {
            pendingExpectations.append((snapshot, expectation))
        }
    }
}

private struct ViewerSnippetLifecycleProbe: View {
    @Bindable var viewerState: ViewerState
    let recorder: ViewerSnippetLifecycleRecorder

    var body: some View {
        ViewerContentView(
            viewerState: viewerState,
            onPaste: { _, _ in },
            onClose: {},
            onClearHistory: {}
        )
        .onChange(of: viewerState.snippetIDs, initial: true) { _, snippetIDs in
            recorder.record(
                snippetIDs: snippetIDs,
                selectedSnippetID: viewerState.selectedSnippetID
            )
        }
    }
}

@MainActor
final class ViewerContentLifecycleTests: XCTestCase {
    private struct Fixture {
        let context: ModelContext
        let folder: SnippetFolder
        let firstID: PersistentIdentifier
        let secondID: PersistentIdentifier
        let state: ViewerState
        let recorder: ViewerSnippetLifecycleRecorder
        let window: NSWindow
    }

    func testMountedViewSynchronizesSnippetSelectionAcrossEditorMutations() async throws {
        let fixture = try makeFixture()
        defer { fixture.window.contentView = nil }

        await waitForSnippetState(
            [fixture.firstID, fixture.secondID],
            selectedSnippetID: fixture.firstID,
            recorder: fixture.recorder,
            description: "mounted viewer synchronized initial snippets"
        )

        let createResult = try SnippetMutations.createSnippet(
            title: "Third",
            content: "third",
            folderID: fixture.folder.persistentModelID,
            in: fixture.context
        )
        let thirdID = try XCTUnwrap(createResult.selectedSnippetID)
        await waitForSnippetState(
            [fixture.firstID, fixture.secondID, thirdID],
            selectedSnippetID: fixture.firstID,
            recorder: fixture.recorder,
            description: "mounted viewer synchronized inserted snippet"
        )

        fixture.state.selectedSnippetID = fixture.secondID
        let moveResult = try SnippetMutations.moveSnippet(
            id: fixture.secondID,
            to: fixture.folder.persistentModelID,
            before: nil,
            in: fixture.context
        )
        XCTAssertNotNil(moveResult)
        await waitForSnippetState(
            [fixture.firstID, thirdID, fixture.secondID],
            selectedSnippetID: fixture.secondID,
            recorder: fixture.recorder,
            description: "mounted viewer synchronized reordered snippets"
        )

        _ = try SnippetMutations.deleteSnippet(
            id: fixture.secondID,
            in: fixture.context
        )
        await waitForSnippetState(
            [fixture.firstID, thirdID],
            selectedSnippetID: fixture.firstID,
            recorder: fixture.recorder,
            description: "mounted viewer synchronized deleted snippet"
        )
    }

    func testMountedViewSynchronizesSelectedSnippetMovedAcrossFolders() async throws {
        let fixture = try makeFixture()
        defer { fixture.window.contentView = nil }

        await waitForSnippetState(
            [fixture.firstID, fixture.secondID],
            selectedSnippetID: fixture.firstID,
            recorder: fixture.recorder,
            description: "mounted viewer synchronized initial snippets"
        )

        let folderResult = try SnippetMutations.createFolder(
            title: "Destination",
            in: fixture.context
        )
        let destinationID = try XCTUnwrap(folderResult.selectedFolderID)
        let createResult = try SnippetMutations.createSnippet(
            title: "Existing",
            content: "existing",
            folderID: destinationID,
            in: fixture.context
        )
        let existingID = try XCTUnwrap(createResult.selectedSnippetID)
        await waitForSnippetState(
            [fixture.firstID, fixture.secondID, existingID],
            selectedSnippetID: fixture.firstID,
            recorder: fixture.recorder,
            description: "mounted viewer synchronized destination folder"
        )

        fixture.state.selectedSnippetID = fixture.secondID
        let moveResult = try SnippetMutations.moveSnippet(
            id: fixture.secondID,
            to: destinationID,
            before: nil,
            in: fixture.context
        )
        XCTAssertEqual(moveResult?.selectedSnippetID, fixture.secondID)
        await waitForSnippetState(
            [fixture.firstID, existingID, fixture.secondID],
            selectedSnippetID: fixture.secondID,
            recorder: fixture.recorder,
            description: "mounted viewer synchronized cross-folder move"
        )
    }

    private func makeFixture() throws -> Fixture {
        let container = try makeContainer()
        let context = container.mainContext
        let folder = SnippetFolder(title: "Folder", sortOrder: 0)
        let firstSnippet = makeSnippet(title: "First", sortOrder: 0, folder: folder)
        let secondSnippet = makeSnippet(title: "Second", sortOrder: 1, folder: folder)
        [folder].forEach(context.insert)
        [firstSnippet, secondSnippet].forEach(context.insert)
        try context.save()

        let state = ViewerState()
        let recorder = ViewerSnippetLifecycleRecorder()
        let rootView = ViewerSnippetLifecycleProbe(
            viewerState: state,
            recorder: recorder
        )
        .modelContainer(container)

        return Fixture(
            context: context,
            folder: folder,
            firstID: firstSnippet.persistentModelID,
            secondID: secondSnippet.persistentModelID,
            state: state,
            recorder: recorder,
            window: makeWindow(rootView: rootView)
        )
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSnippet(
        title: String,
        sortOrder: Int,
        folder: SnippetFolder
    ) -> Snippet {
        Snippet(
            title: title,
            content: title.lowercased(),
            sortOrder: sortOrder,
            folder: folder
        )
    }

    private func makeWindow<Content: View>(rootView: Content) -> NSWindow {
        let hostingView = NSHostingView(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        return window
    }

    private func waitForSnippetState(
        _ snippetIDs: [PersistentIdentifier],
        selectedSnippetID: PersistentIdentifier?,
        recorder: ViewerSnippetLifecycleRecorder,
        description: String
    ) async {
        let stateExpectation = expectation(description: description)
        recorder.expect(
            snippetIDs: snippetIDs,
            selectedSnippetID: selectedSnippetID,
            expectation: stateExpectation
        )
        await fulfillment(of: [stateExpectation], timeout: 1.0)
    }
}
