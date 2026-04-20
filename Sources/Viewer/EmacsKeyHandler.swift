import AppKit

enum EmacsKeyHandler {
    static func handle(event: NSEvent) -> ViewerAction? {
        // Return is handled by keyCode at the top level.
        // Ctrl+Return → plain text, bare Return → original format.
        if event.keyCode == 36 {
            return event.modifierFlags.contains(.control)
                ? .paste(.plainText)
                : .paste(.original)
        }
        if event.modifierFlags.contains(.control) {
            return handleControl(event: event)
        }
        return handlePlain(event: event)
    }

    private static func handleControl(event: NSEvent) -> ViewerAction? {
        switch event.charactersIgnoringModifiers {
        case "n": .move(.down)
        case "p": .move(.up)
        case "a": .jumpToStart
        case "e": .jumpToEnd
        case "g": .close
        default:  nil
        }
    }

    private static func handlePlain(event: NSEvent) -> ViewerAction? {
        switch event.keyCode {
        case 53:  .close      // Escape
        case 125: .move(.down) // Down arrow
        case 126: .move(.up)   // Up arrow
        default:  nil
        }
    }
}
