import XCTest
import AppKit
@testable import Yank

final class EmacsKeyHandlerTabShortcutTests: XCTestCase {

    // MARK: - Cmd+Shift bracket tab switching

    func testCommandShiftRightBracket_switchesTabForward() {
        XCTAssertEqual(
            commandShiftAction(keyCode: 30, character: "}"),
            .switchTab(.forward)
        )
    }

    func testCommandShiftLeftBracket_switchesTabBackward() {
        XCTAssertEqual(
            commandShiftAction(keyCode: 33, character: "{"),
            .switchTab(.backward)
        )
    }

    // Brackets must match by produced character, not physical keyCode:
    // on JIS layouts "]" sits at keyCode 42 (ANSI backslash position).
    func testCommandShiftBracket_matchesByCharacterNotKeyCode() {
        XCTAssertEqual(
            commandShiftAction(keyCode: 42, character: "}"),
            .switchTab(.forward)
        )
    }

    func testCommandShiftUnshiftedBrackets_switchTabs() {
        XCTAssertEqual(
            commandShiftAction(keyCode: 33, character: "["),
            .switchTab(.backward)
        )
        XCTAssertEqual(
            commandShiftAction(keyCode: 30, character: "]"),
            .switchTab(.forward)
        )
    }

    func testCommandShiftBracket_withStaleEventFlags_doesNotSwitchTab() {
        let event = makeKeyEvent(
            keyCode: 30,
            character: "}",
            modifierFlags: [.command, .shift]
        )
        XCTAssertNil(EmacsKeyHandler.handle(event: event, trackedModifiers: []))
    }

    // The tab shortcut requires the exact Cmd+Shift chord; superset chords
    // must stay inert so a `.contains`-style refactor of the modifier gate
    // cannot silently widen the shortcut.
    func testCommandShiftOptionBracket_doesNotSwitchTab() {
        let event = makeKeyEvent(
            keyCode: 30,
            character: "}",
            modifierFlags: [.command, .shift, .option]
        )
        XCTAssertNil(
            EmacsKeyHandler.handle(
                event: event,
                trackedModifiers: [.command, .shift, .option]
            )
        )
    }

    func testCommandControlShiftBracket_doesNotSwitchTab() {
        let event = makeKeyEvent(
            keyCode: 30,
            character: "}",
            modifierFlags: [.command, .shift, .control]
        )
        XCTAssertNil(
            EmacsKeyHandler.handle(
                event: event,
                trackedModifiers: [.command, .shift, .control]
            )
        )
    }

    // MARK: - Cmd+Shift chord swallowing

    // While the Cmd+Shift chord is held, only the bracket tab shortcuts
    // are active; Return/Escape/Delete must not fire their unmodified
    // actions (paste/close/delete). Intentional per ADR 0012.
    func testCommandShiftReturn_doesNotPaste() {
        XCTAssertNil(commandShiftAction(keyCode: 36))
    }

    func testCommandShiftEscape_doesNotClose() {
        XCTAssertNil(commandShiftAction(keyCode: 53))
    }

    func testCommandShiftDelete_doesNotDeleteSelectedItem() {
        XCTAssertNil(commandShiftAction(keyCode: 51))
    }

    // MARK: - C-f / C-b stay unbound for a future snippet editor (ADR 0012)

    func testControlF_doesNotSwitchTab() {
        let event = makeControlKeyEvent(character: "f")
        XCTAssertNil(
            EmacsKeyHandler.handle(event: event, trackedModifiers: .control)
        )
    }

    func testControlB_doesNotSwitchTab() {
        let event = makeControlKeyEvent(character: "b")
        XCTAssertNil(
            EmacsKeyHandler.handle(event: event, trackedModifiers: .control)
        )
    }

    // MARK: - Helpers

    private func commandShiftAction(
        keyCode: UInt16,
        character: String = ""
    ) -> ViewerAction? {
        EmacsKeyHandler.handle(
            event: makeKeyEvent(
                keyCode: keyCode,
                character: character,
                modifierFlags: [.command, .shift]
            ),
            trackedModifiers: [.command, .shift]
        )
    }

    private func makeControlKeyEvent(character: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .control,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0
        )!
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        character: String = "",
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
