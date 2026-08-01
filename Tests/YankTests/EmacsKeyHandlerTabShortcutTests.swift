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
        XCTAssertNil(EmacsKeyHandler.action(event: event, trackedModifiers: []))
    }

    func testCommandShiftOptionBracket_whenOptionIsLayoutRequired_switchesTab() {
        let event = makeKeyEvent(
            keyCode: 30,
            character: "}",
            modifierFlags: [.command, .shift, .option]
        )
        XCTAssertEqual(
            EmacsKeyHandler.handle(
                event: event,
                trackedModifiers: [.command, .shift, .option],
                translateCharacter: { modifiers in
                    modifiers.contains(.option) ? "}" : "0"
                }
            ),
            .action(.switchTab(.forward))
        )
    }

    // Option is accepted only when the current layout needs it to produce
    // the bracket. A redundant Option modifier remains an unrelated chord.
    func testCommandShiftOptionBracket_whenOptionIsNotRequired_isUnhandled() {
        let event = makeKeyEvent(
            keyCode: 30,
            character: "}",
            modifierFlags: [.command, .shift, .option]
        )
        XCTAssertEqual(
            EmacsKeyHandler.handle(
                event: event,
                trackedModifiers: [.command, .shift, .option],
                translateCharacter: { _ in "}" }
            ),
            .unhandled
        )
    }

    func testCommandControlShiftBracket_doesNotSwitchTab() {
        let event = makeKeyEvent(
            keyCode: 30,
            character: "}",
            modifierFlags: [.command, .shift, .control]
        )
        XCTAssertEqual(
            EmacsKeyHandler.handle(
                event: event,
                trackedModifiers: [.command, .shift, .control]
            ),
            .unhandled
        )
    }

    // MARK: - Cmd+Shift chord swallowing

    // While the Cmd+Shift chord is held, only the bracket tab shortcuts
    // are active; Return/Escape/Delete must not fire their unmodified
    // actions (paste/close/delete). Intentional per ADR 0012.
    func testCommandShiftReturn_doesNotPaste() {
        XCTAssertEqual(commandShiftResult(keyCode: 36), .consumed)
    }

    func testCommandShiftEscape_doesNotClose() {
        XCTAssertEqual(commandShiftResult(keyCode: 53), .consumed)
    }

    func testCommandShiftDelete_doesNotDeleteSelectedItem() {
        XCTAssertEqual(commandShiftResult(keyCode: 51), .consumed)
    }

    // MARK: - C-f / C-b stay unbound for a future snippet editor (ADR 0012)

    func testControlF_doesNotSwitchTab() {
        let event = makeControlKeyEvent(character: "f")
        XCTAssertNil(
            EmacsKeyHandler.action(event: event, trackedModifiers: .control)
        )
    }

    func testControlB_doesNotSwitchTab() {
        let event = makeControlKeyEvent(character: "b")
        XCTAssertNil(
            EmacsKeyHandler.action(event: event, trackedModifiers: .control)
        )
    }

    // MARK: - Helpers

    private func commandShiftAction(
        keyCode: UInt16,
        character: String = ""
    ) -> ViewerAction? {
        EmacsKeyHandler.action(
            event: makeKeyEvent(
                keyCode: keyCode,
                character: character,
                modifierFlags: [.command, .shift]
            ),
            trackedModifiers: [.command, .shift],
            translateCharacter: { _ in character }
        )
    }

    private func commandShiftResult(
        keyCode: UInt16,
        character: String = ""
    ) -> ViewerKeyHandlingResult {
        EmacsKeyHandler.handle(
            event: makeKeyEvent(
                keyCode: keyCode,
                character: character,
                modifierFlags: [.command, .shift]
            ),
            trackedModifiers: [.command, .shift],
            translateCharacter: { _ in character }
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
