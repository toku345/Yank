import XCTest
import AppKit
@testable import Yank

final class EmacsKeyHandlerTests: XCTestCase {

    // MARK: - Control key bindings

    func testControlN_movesDown() {
        let event = makeControlKeyEvent(character: "n")
        XCTAssertEqual(
            EmacsKeyHandler.handle(event: event, trackedModifiers: .control),
            .move(.down)
        )
    }

    func testControlP_movesUp() {
        let event = makeControlKeyEvent(character: "p")
        XCTAssertEqual(
            EmacsKeyHandler.handle(event: event, trackedModifiers: .control),
            .move(.up)
        )
    }

    func testControlA_jumpsToStart() {
        let event = makeControlKeyEvent(character: "a")
        XCTAssertEqual(
            EmacsKeyHandler.handle(event: event, trackedModifiers: .control),
            .jumpToStart
        )
    }

    func testControlE_jumpsToEnd() {
        let event = makeControlKeyEvent(character: "e")
        XCTAssertEqual(
            EmacsKeyHandler.handle(event: event, trackedModifiers: .control),
            .jumpToEnd
        )
    }

    func testControlG_closes() {
        let event = makeControlKeyEvent(character: "g")
        XCTAssertEqual(
            EmacsKeyHandler.handle(event: event, trackedModifiers: .control),
            .close
        )
    }

    // MARK: - Stale modifier flag regressions

    // Return + event.modifierFlags=.control but trackedModifiers empty →
    // must fall back to .paste(.original). Guards against trusting stale flags.
    func testReturn_withStaleEventControlFlag_pastesOriginal() {
        let event = makeKeyEvent(keyCode: 36, modifierFlags: .control)
        XCTAssertEqual(
            EmacsKeyHandler.handle(event: event, trackedModifiers: []),
            .paste(.original)
        )
    }

    // Return + trackedModifiers=.control and event.modifierFlags=[] →
    // must resolve to .paste(.plainText). Proves tracked state is sufficient.
    func testReturn_withTrackedControlOnly_pastesPlainText() {
        let event = makeKeyEvent(keyCode: 36)
        XCTAssertEqual(
            EmacsKeyHandler.handle(event: event, trackedModifiers: .control),
            .paste(.plainText)
        )
    }

    // Bare "n" + event.modifierFlags=.control (stale) but trackedModifiers empty →
    // must NOT route through handleControl. Prevents spurious navigation.
    func testBareN_withStaleEventControlFlag_returnsNil() {
        let event = makeControlKeyEvent(character: "n")
        XCTAssertNil(EmacsKeyHandler.handle(event: event, trackedModifiers: []))
    }

    func testBareG_withStaleEventControlFlag_doesNotClose() {
        let event = makeControlKeyEvent(character: "g")
        XCTAssertNil(EmacsKeyHandler.handle(event: event, trackedModifiers: []))
    }

    // MARK: - Plain key bindings

    func testReturn_pastesOriginal() {
        let event = makeKeyEvent(keyCode: 36)
        XCTAssertEqual(EmacsKeyHandler.handle(event: event), .paste(.original))
    }

    func testControlReturn_pastesPlainText() {
        let event = makeKeyEvent(keyCode: 36, modifierFlags: .control)
        XCTAssertEqual(
            EmacsKeyHandler.handle(event: event, trackedModifiers: .control),
            .paste(.plainText)
        )
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
        XCTAssertNil(EmacsKeyHandler.handle(event: event, trackedModifiers: .control))
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

    private func makeKeyEvent(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
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
