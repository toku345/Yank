import AppKit
import SwiftData
import XCTest
@testable import Yank

@MainActor
final class ViewerPanelTests: XCTestCase {
    private static let currentUptime: TimeInterval = 10
    private var retainedModelContainer: ModelContainer?

    override func tearDown() {
        retainedModelContainer = nil
        super.tearDown()
    }

    func testSendEvent_staleRepeatedMoveIsDiscarded() throws {
        let (state, _) = try makeStateWithOneItem()
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeDownArrowEvent(timestamp: 9.899, isARepeat: true)
        )

        XCTAssertNil(state.selectedHistoryID)
    }

    func testSendEvent_freshRepeatedMoveDispatches() throws {
        let (state, itemID) = try makeStateWithOneItem()
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeDownArrowEvent(timestamp: 9.901, isARepeat: true)
        )

        XCTAssertEqual(state.selectedHistoryID, itemID)
    }

    func testSendEvent_nonRepeatedMoveDispatchesRegardlessOfAge() throws {
        let (state, itemID) = try makeStateWithOneItem()
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeDownArrowEvent(timestamp: 9.899, isARepeat: false)
        )

        XCTAssertEqual(state.selectedHistoryID, itemID)
    }

    func testSendEvent_commandShiftRightBracketSwitchesTabForward() throws {
        let state = ViewerState()
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeFlagsChangedEvent(modifierFlags: [.command, .shift])
        )
        panel.sendEvent(
            try makeCharacterEvent(
                character: "}",
                keyCode: 30,
                modifierFlags: [.command, .shift]
            )
        )

        XCTAssertEqual(state.selectedTab, .snippets)
    }

    func testSendEvent_commandShiftLeftBracketSwitchesTabBackward() throws {
        let state = ViewerState()
        state.selectedTab = .snippets
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeFlagsChangedEvent(modifierFlags: [.command, .shift])
        )
        panel.sendEvent(
            try makeCharacterEvent(
                character: "{",
                keyCode: 33,
                modifierFlags: [.command, .shift]
            )
        )

        XCTAssertEqual(state.selectedTab, .history)
    }

    func testSendEvent_staleEventCommandShiftFlagsDoNotSwitchTab() throws {
        let state = ViewerState()
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeCharacterEvent(
                character: "}",
                keyCode: 30,
                modifierFlags: [.command, .shift]
            )
        )

        XCTAssertEqual(state.selectedTab, .history)
    }

    func testHandleViewerKeyDown_commandShiftReturnIsConsumed() throws {
        let state = ViewerState()
        let panel = makePanel(viewerState: state)
        panel.sendEvent(
            try makeFlagsChangedEvent(modifierFlags: [.command, .shift])
        )

        let wasHandled = panel.handleViewerKeyDown(
            try makeCharacterEvent(
                character: "",
                keyCode: 36,
                modifierFlags: [.command, .shift]
            )
        )

        XCTAssertTrue(wasHandled)
        XCTAssertNil(state.pendingAction)
    }

    func testSendEvent_modifierReleaseRestoresEscapeClose() throws {
        let state = ViewerState()
        let panel = makePanel(viewerState: state)

        panel.sendEvent(
            try makeFlagsChangedEvent(modifierFlags: [.command, .shift])
        )
        panel.sendEvent(
            try makeFlagsChangedEvent(modifierFlags: [])
        )
        panel.sendEvent(
            try makeCharacterEvent(
                character: "",
                keyCode: 53,
                modifierFlags: []
            )
        )

        XCTAssertEqual(state.pendingAction, .close)
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
        let schema = YankSchema.current
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        retainedModelContainer = container
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
        state.replaceHistoryItems(with: [item.persistentModelID])
        state.selectedHistoryID = nil
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

    private func makeFlagsChangedEvent(
        modifierFlags: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: Self.currentUptime,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 59
            )
        )
    }

    private func makeCharacterEvent(
        character: String,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: Self.currentUptime,
                windowNumber: 0,
                context: nil,
                characters: character,
                charactersIgnoringModifiers: character,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}
