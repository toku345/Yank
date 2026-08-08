import AppKit

enum ViewerKeyHandlingResult: Equatable {
    case action(ViewerAction)
    case consumed
    case unhandled
}

enum EmacsKeyHandler {
    typealias CharacterTranslator = (NSEvent.ModifierFlags) -> String?

    private static let shortcutModifierMask: NSEvent.ModifierFlags = [
        .command, .control, .option, .shift
    ]

    /// - Parameters:
    ///   - event: The raw key-down event from `sendEvent`.
    ///   - trackedModifiers: Modifier flags tracked via `flagsChanged` events
    ///     in ViewerPanel. Used for modifier-sensitive dispatch because
    ///     `event.modifierFlags` carries stale state from prior key combos
    ///     (see ViewerPanel.trackedModifiers).
    static func handle(
        event: NSEvent,
        trackedModifiers: NSEvent.ModifierFlags = [],
        translateCharacter: CharacterTranslator? = nil
    ) -> ViewerKeyHandlingResult {
        let shortcutModifiers = trackedModifiers.intersection(shortcutModifierMask)
        if shortcutModifiers == [.command, .shift] {
            let character = translatedCharacter(
                event: event,
                modifiers: .shift,
                translateCharacter: translateCharacter
            )
            return tabAction(for: character).map(ViewerKeyHandlingResult.action)
                ?? .consumed
        }
        if shortcutModifiers == [.command, .option, .shift] {
            return handleLayoutRequiredOptionShortcut(
                event: event,
                translateCharacter: translateCharacter
            )
        }
        // Ctrl+Return → plain text, bare Return → original format.
        if isReturnKey(event.keyCode) {
            let action: ViewerAction = trackedModifiers.contains(.control)
                ? .paste(.plainText) : .paste(.original)
            return .action(action)
        }
        if trackedModifiers.contains(.control) {
            return result(for: handleControl(event: event))
        }
        return result(for: handlePlain(event: event))
    }

    private static func isReturnKey(_ keyCode: UInt16) -> Bool {
        keyCode == 36 || keyCode == 76 // Main Return or keypad Enter
    }

    static func action(
        event: NSEvent,
        trackedModifiers: NSEvent.ModifierFlags = [],
        translateCharacter: CharacterTranslator? = nil
    ) -> ViewerAction? {
        guard case .action(let action) = handle(
            event: event,
            trackedModifiers: trackedModifiers,
            translateCharacter: translateCharacter
        ) else { return nil }
        return action
    }

    private static func handleLayoutRequiredOptionShortcut(
        event: NSEvent,
        translateCharacter: CharacterTranslator?
    ) -> ViewerKeyHandlingResult {
        let withOption = translatedCharacter(
            event: event,
            modifiers: [.option, .shift],
            translateCharacter: translateCharacter
        )
        guard let action = tabAction(for: withOption) else { return .unhandled }

        let withoutOption = translatedCharacter(
            event: event,
            modifiers: .shift,
            translateCharacter: translateCharacter
        )
        guard tabAction(for: withoutOption) == nil else { return .unhandled }
        return .action(action)
    }

    private static func translatedCharacter(
        event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        translateCharacter: CharacterTranslator?
    ) -> String? {
        if let translateCharacter {
            return translateCharacter(modifiers)
        }
        return event.characters(byApplyingModifiers: modifiers)
    }

    private static func tabAction(for character: String?) -> ViewerAction? {
        switch character {
        case "[", "{": .switchTab(.backward)
        case "]", "}": .switchTab(.forward)
        default: nil
        }
    }

    private static func result(for action: ViewerAction?) -> ViewerKeyHandlingResult {
        action.map(ViewerKeyHandlingResult.action) ?? .unhandled
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
        case 51:  event.isARepeat ? nil : .deleteSelected // Delete / Backspace
        case 117: event.isARepeat ? nil : .deleteSelected // Forward Delete
        case 125: .move(.down) // Down arrow
        case 126: .move(.up)   // Up arrow
        default:  nil
        }
    }
}
