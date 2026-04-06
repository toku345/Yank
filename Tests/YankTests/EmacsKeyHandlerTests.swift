import XCTest
import AppKit
@testable import Yank

final class EmacsKeyHandlerTests: XCTestCase {

    // MARK: - Control key bindings

    func testControlN_movesDown() {
        let event = makeControlKeyEvent(character: "n")
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .move(.down))
    }

    func testControlP_movesUp() {
        let event = makeControlKeyEvent(character: "p")
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .move(.up))
    }

    func testControlA_jumpsToStart() {
        let event = makeControlKeyEvent(character: "a")
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .jumpToStart)
    }

    func testControlE_jumpsToEnd() {
        let event = makeControlKeyEvent(character: "e")
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .jumpToEnd)
    }

    func testControlG_closes() {
        let event = makeControlKeyEvent(character: "g")
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .close)
    }

    // MARK: - Plain key bindings

    func testReturn_pastes() {
        let event = makeKeyEvent(keyCode: 36)
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .paste)
    }

    func testEscape_closes() {
        let event = makeKeyEvent(keyCode: 53)
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .close)
    }

    func testDownArrow_movesDown() {
        let event = makeKeyEvent(keyCode: 125)
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .move(.down))
    }

    func testUpArrow_movesUp() {
        let event = makeKeyEvent(keyCode: 126)
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .move(.up))
    }

    // MARK: - Unhandled keys

    func testUnhandledKey_returnsNil() {
        let event = makeKeyEvent(keyCode: 0) // 'a' key
        XCTAssertNil(EmacsKeyHandler.handle(event: event))
    }

    func testUnhandledControlKey_returnsNil() {
        let event = makeControlKeyEvent(character: "x")
        XCTAssertNil(EmacsKeyHandler.handle(event: event))
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
