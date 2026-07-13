import AppKit
import SwiftData
import XCTest
@testable import Yank

@MainActor
final class ViewerPanelTests: XCTestCase {
    private static let currentUptime: TimeInterval = 10

    func testSendEvent_staleRepeatedMoveIsDiscarded() throws {
        let (state, _) = try makeStateWithOneItem()
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeDownArrowEvent(timestamp: 9.899, isARepeat: true)
        )

        XCTAssertNil(state.selectedID)
    }

    func testSendEvent_freshRepeatedMoveDispatches() throws {
        let (state, itemID) = try makeStateWithOneItem()
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeDownArrowEvent(timestamp: 9.901, isARepeat: true)
        )

        XCTAssertEqual(state.selectedID, itemID)
    }

    func testSendEvent_nonRepeatedMoveDispatchesRegardlessOfAge() throws {
        let (state, itemID) = try makeStateWithOneItem()
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeDownArrowEvent(timestamp: 9.899, isARepeat: false)
        )

        XCTAssertEqual(state.selectedID, itemID)
    }

    private func makePanel(viewerState: ViewerState) -> ViewerPanel {
        ViewerPanel(
            viewerState: viewerState,
            contentView: NSView(),
            currentUptime: { Self.currentUptime }
        )
    }

    private func makeStateWithOneItem() throws -> (
        state: ViewerState,
        itemID: PersistentIdentifier
    ) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ClipItem.self,
            configurations: config
        )
        let context = ModelContext(container)
        let item = ClipItem(
            title: "Item",
            primaryType: "public.utf8-plain-text",
            availableTypes: ["public.utf8-plain-text"],
            stringValue: "content"
        )
        context.insert(item)
        try context.save()

        let state = ViewerState()
        state.itemIDs = [item.persistentModelID]
        return (state, item.persistentModelID)
    }

    private func makeDownArrowEvent(
        timestamp: TimeInterval,
        isARepeat: Bool
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: isARepeat,
                keyCode: 125
            )
        )
    }
}
