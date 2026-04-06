import XCTest
import AppKit
@testable import Yank

@MainActor
final class EmacsKeyHandlerTests: XCTestCase {

    private var state: KeyboardState!

    override func setUp() {
        super.setUp()
        state = KeyboardState()
    }

    // MARK: - Control key bindings

    func testControlN_movesDown() {
        let event = makeControlKeyEvent(character: "n")
        XCTAssertTrue(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertEqual(state.moveDirection, .moveDown)
    }

    func testControlP_movesUp() {
        let event = makeControlKeyEvent(character: "p")
        XCTAssertTrue(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertEqual(state.moveDirection, .moveUp)
    }

    func testControlA_jumpsToStart() {
        let event = makeControlKeyEvent(character: "a")
        XCTAssertTrue(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertTrue(state.shouldJumpToStart)
    }

    func testControlE_jumpsToEnd() {
        let event = makeControlKeyEvent(character: "e")
        XCTAssertTrue(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertTrue(state.shouldJumpToEnd)
    }

    func testControlG_closes() {
        let event = makeControlKeyEvent(character: "g")
        XCTAssertTrue(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertTrue(state.shouldClose)
    }

    // MARK: - Plain key bindings

    func testReturn_pastes() {
        let event = makeKeyEvent(keyCode: 36) // Return
        XCTAssertTrue(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertTrue(state.shouldPaste)
    }

    func testEscape_closes() {
        let event = makeKeyEvent(keyCode: 53) // Escape
        XCTAssertTrue(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertTrue(state.shouldClose)
    }

    func testDownArrow_movesDown() {
        let event = makeKeyEvent(keyCode: 125) // Down arrow
        XCTAssertTrue(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertEqual(state.moveDirection, .moveDown)
    }

    func testUpArrow_movesUp() {
        let event = makeKeyEvent(keyCode: 126) // Up arrow
        XCTAssertTrue(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertEqual(state.moveDirection, .moveUp)
    }

    // MARK: - Unhandled keys

    func testUnhandledKey_returnsFalse() {
        let event = makeKeyEvent(keyCode: 0) // 'a' key
        XCTAssertFalse(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertNil(state.moveDirection)
        XCTAssertFalse(state.shouldPaste)
        XCTAssertFalse(state.shouldClose)
        XCTAssertFalse(state.shouldJumpToStart)
        XCTAssertFalse(state.shouldJumpToEnd)
    }

    func testUnhandledControlKey_returnsFalse() {
        let event = makeControlKeyEvent(character: "x")
        XCTAssertFalse(EmacsKeyHandler.handle(event: event, state: state))
        XCTAssertNil(state.moveDirection)
        XCTAssertFalse(state.shouldPaste)
        XCTAssertFalse(state.shouldClose)
    }

    // MARK: - Helpers

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

    private func makeKeyEvent(keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
