import SwiftData
import XCTest
@testable import Yank

@MainActor
final class HistoryRowContractTests: XCTestCase {
    func testAccessibilityLabelUsesItemTitle() throws {
        let fixture = try makeFixture()
        let contract = makeContract(for: fixture.item, in: fixture)

        XCTAssertEqual(contract.accessibilityLabel, fixture.item.title)
    }

    func testSelectionTracksViewerState() throws {
        let fixture = try makeFixture()
        let contract = makeContract(for: fixture.item, in: fixture)

        XCTAssertNil(fixture.viewerState.selectedID)
        XCTAssertFalse(contract.isSelected)

        fixture.viewerState.selectedID = fixture.otherItem.persistentModelID
        XCTAssertFalse(contract.isSelected)

        fixture.viewerState.selectedID = fixture.item.persistentModelID
        XCTAssertTrue(contract.isSelected)
    }

    func testActivateSelectsItemBeforeCallingCallback() throws {
        let fixture = try makeFixture()
        fixture.viewerState.selectedID = fixture.otherItem.persistentModelID
        var selectedIDDuringCallback: PersistentIdentifier?
        var activatedItem: ClipItem?
        let contract = HistoryRowContract(
            item: fixture.item,
            viewerState: fixture.viewerState,
            onActivate: { item in
                selectedIDDuringCallback = fixture.viewerState.selectedID
                activatedItem = item
            }
        )

        contract.activate()

        XCTAssertEqual(
            selectedIDDuringCallback,
            fixture.item.persistentModelID
        )
        XCTAssertTrue(activatedItem === fixture.item)
        XCTAssertEqual(
            fixture.viewerState.selectedID,
            fixture.item.persistentModelID
        )
    }

    func testActivateWithoutCallbackStillSelectsItem() throws {
        let fixture = try makeFixture()
        let contract = makeContract(for: fixture.item, in: fixture)

        contract.activate()

        XCTAssertEqual(
            fixture.viewerState.selectedID,
            fixture.item.persistentModelID
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let item: ClipItem
        let otherItem: ClipItem
        let viewerState: ViewerState
    }

    private func makeFixture() throws -> Fixture {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ClipItem.self,
            configurations: config
        )
        let context = ModelContext(container)
        let item = makeItem(title: "Target clip")
        let otherItem = makeItem(title: "Other clip")
        context.insert(item)
        context.insert(otherItem)
        try context.save()

        return Fixture(
            container: container,
            context: context,
            item: item,
            otherItem: otherItem,
            viewerState: ViewerState()
        )
    }

    private func makeContract(
        for item: ClipItem,
        in fixture: Fixture
    ) -> HistoryRowContract {
        HistoryRowContract(
            item: item,
            viewerState: fixture.viewerState,
            onActivate: nil
        )
    }

    private func makeItem(title: String) -> ClipItem {
        ClipItem(
            title: title,
            primaryType: "public.utf8-plain-text",
            availableTypes: ["public.utf8-plain-text"],
            stringValue: title
        )
    }
}
