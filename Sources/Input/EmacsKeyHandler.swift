import AppKit

@MainActor
final class KeyboardState: ObservableObject {
    enum MoveDirection {
        case up, down
    }

    @Published var moveDirection: MoveDirection?
    @Published var shouldPaste: Bool = false
    @Published var shouldClose: Bool = false
    @Published var shouldJumpToStart: Bool = false
    @Published var shouldJumpToEnd: Bool = false
}

enum EmacsKeyHandler {
    /// キーイベントを処理し、ハンドルした場合は true を返す
    @MainActor
    static func handle(event: NSEvent, state: KeyboardState) -> Bool {
        let isControl = event.modifierFlags.contains(.control)

        if isControl {
            switch event.charactersIgnoringModifiers {
            case "n":
                state.moveDirection = .down
                return true
            case "p":
                state.moveDirection = .up
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
                break
            }
        }

        switch event.keyCode {
        case 36: // Return
            state.shouldPaste = true
            return true
        case 53: // Escape
            state.shouldClose = true
            return true
        case 125: // Down arrow
            state.moveDirection = .down
            return true
        case 126: // Up arrow
            state.moveDirection = .up
            return true
        default:
            return false
        }
    }
}
