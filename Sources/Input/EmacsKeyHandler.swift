import AppKit

@MainActor
final class KeyboardState: ObservableObject {
    enum MoveDirection {
        case moveUp, moveDown
    }

    @Published var moveDirection: MoveDirection?
    @Published var shouldPaste: Bool = false
    @Published var shouldClose: Bool = false
    @Published var shouldJumpToStart: Bool = false
    @Published var shouldJumpToEnd: Bool = false
}

enum EmacsKeyHandler {
    @MainActor
    static func handle(event: NSEvent, state: KeyboardState) -> Bool {
        if event.modifierFlags.contains(.control) {
            return handleControl(event: event, state: state)
        }
        return handlePlain(event: event, state: state)
    }

    @MainActor
    private static func handleControl(event: NSEvent, state: KeyboardState) -> Bool {
        switch event.charactersIgnoringModifiers {
        case "n":
            state.moveDirection = .moveDown
            return true
        case "p":
            state.moveDirection = .moveUp
            return true
        case "a":
            state.shouldJumpToStart = true
            return true
        case "e":
            state.shouldJumpToEnd = true
            return true
        case "g":
            state.shouldClose = true
            return true
        default:
            return false
        }
    }

    @MainActor
    private static func handlePlain(event: NSEvent, state: KeyboardState) -> Bool {
        switch event.keyCode {
        case 36: // Return
            state.shouldPaste = true
            return true
        case 53: // Escape
            state.shouldClose = true
            return true
        case 125: // Down arrow
            state.moveDirection = .moveDown
            return true
        case 126: // Up arrow
            state.moveDirection = .moveUp
            return true
        default:
            return false
        }
    }
}
