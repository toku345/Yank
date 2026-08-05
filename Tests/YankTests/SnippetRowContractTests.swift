import SwiftData
import XCTest
@testable import Yank

@MainActor
final class SnippetRowContractTests: XCTestCase {
    func testAccessibilityLabelUsesSnippetTitle() throws {
        let fixture = try makeFixture()
        let contract = makeContract(for: fixture.snippet, in: fixture)

        XCTAssertEqual(contract.accessibilityLabel, fixture.snippet.title)
    }

    func testSelectionTracksViewerState() throws {
        let fixture = try makeFixture()
        let contract = makeContract(for: fixture.snippet, in: fixture)

        XCTAssertNil(fixture.viewerState.selectedSnippetID)
        XCTAssertFalse(contract.isSelected)

        fixture.viewerState.selectedSnippetID = fixture.otherSnippet.persistentModelID
        XCTAssertFalse(contract.isSelected)

        fixture.viewerState.selectedSnippetID = fixture.snippet.persistentModelID
        XCTAssertTrue(contract.isSelected)
    }

    func testActivateSelectsSnippetBeforeCallingCallback() throws {
        let fixture = try makeFixture()
        fixture.viewerState.selectedSnippetID = fixture.otherSnippet.persistentModelID
        var selectedIDDuringCallback: PersistentIdentifier?
        var activatedSnippet: Snippet?
        let contract = SnippetRowContract(
            snippet: fixture.snippet,
            viewerState: fixture.viewerState,
            onActivate: { snippet in
                selectedIDDuringCallback = fixture.viewerState.selectedSnippetID
                activatedSnippet = snippet
            }
        )

        contract.activate()

        XCTAssertEqual(selectedIDDuringCallback, fixture.snippet.persistentModelID)
        XCTAssertTrue(activatedSnippet === fixture.snippet)
        XCTAssertEqual(
            fixture.viewerState.selectedSnippetID,
            fixture.snippet.persistentModelID
        )
    }

    func testActivateWithoutCallbackStillSelectsSnippet() throws {
        let fixture = try makeFixture()
        let contract = makeContract(for: fixture.snippet, in: fixture)

        contract.activate()

        XCTAssertEqual(
            fixture.viewerState.selectedSnippetID,
            fixture.snippet.persistentModelID
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let folder: SnippetFolder
        let snippet: Snippet
        let otherSnippet: Snippet
        let viewerState: ViewerState
    }

    private func makeFixture() throws -> Fixture {
        let schema = YankSchema.current
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let folder = SnippetFolder(title: "Folder", sortOrder: 0)
        let otherFolder = SnippetFolder(title: "Other", sortOrder: 1)
        let snippet = makeSnippet(title: "Target", folder: folder)
        let otherSnippet = makeSnippet(title: "Other", folder: otherFolder)
        [folder, otherFolder].forEach(context.insert)
        [snippet, otherSnippet].forEach(context.insert)
        try context.save()

        return Fixture(
            container: container,
            folder: folder,
            snippet: snippet,
            otherSnippet: otherSnippet,
            viewerState: ViewerState()
        )
    }

    private func makeContract(
        for snippet: Snippet,
        in fixture: Fixture
    ) -> SnippetRowContract {
        SnippetRowContract(
            snippet: snippet,
            viewerState: fixture.viewerState,
            onActivate: nil
        )
    }

    private func makeSnippet(title: String, folder: SnippetFolder) -> Snippet {
        Snippet(title: title, content: title.lowercased(), sortOrder: 0, folder: folder)
    }
}
