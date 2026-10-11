import AppKit

/// Wording and presentation for the alert shown when Yank cannot open its
/// SwiftData store at launch.
///
/// Kept as a value type so the message contract is testable without presenting
/// UI. The text must state that the existing store was left intact: Yank never
/// deletes or recreates the store when opening fails (ADR 0010).
struct StartupFailureAlert {
    let messageText: String
    let informativeText: String

    init(error: Error, storeURL: URL) {
        messageText = "Yank could not open your clipboard history"
        informativeText = """
            Yank could not open its data store at \(storeURL.path) and has to quit.

            This usually means the store could not be migrated to the schema this version \
            of Yank expects, or that another copy of Yank is already using it. Quit any \
            other copy of Yank and launch it again.

            Your existing data was left untouched: Yank did not delete or recreate the store.

            Details: \(error.localizedDescription)
            """
    }

    @MainActor
    func present() {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = .critical
        alert.runModal()
    }
}
