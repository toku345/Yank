import AppKit

enum EmacsKeyHandler {
    /// - Parameters:
    ///   - event: The raw key-down event from `sendEvent`.
    ///   - trackedModifiers: Modifier flags tracked via `flagsChanged` events
    ///     in ViewerPanel. Used for all control-shortcut dispatch because
    ///     `event.modifierFlags` carries stale state from prior key combos
    ///     (see ViewerPanel.trackedModifiers).
    static func handle(
        event: NSEvent,
        trackedModifiers: NSEvent.ModifierFlags = []
    ) -> ViewerAction? {
        // Ctrl+Return → plain text, bare Return → original format.
        if event.keyCode == 36 {
            return trackedModifiers.contains(.control)
                ? .paste(.plainText)
                : .paste(.original)
        }
        if trackedModifiers.contains(.control) {
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
