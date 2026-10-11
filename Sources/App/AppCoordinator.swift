import AppKit
import SwiftData
import os.log

@MainActor
final class AppCoordinator {
    typealias ModelContainerFactory = @MainActor (Schema, ModelConfiguration) throws -> ModelContainer
    typealias StartupFailurePresenter = @MainActor (StartupFailureAlert) -> Void

    private let logger = Logger(subsystem: "com.toku345.Yank", category: "AppCoordinator")

    private let storeURL: URL?
    private let makeModelContainer: ModelContainerFactory
    private let presentStartupFailure: StartupFailurePresenter

    private(set) var modelContainer: ModelContainer?
    private(set) var clipboardHistoryWriter: ClipboardHistoryWriter?
    private(set) var clipboardMonitor: ClipboardMonitor?
    private(set) var hotKeyManager: HotKeyManager?
    private(set) var panelController: ViewerPanelController?
    private(set) var snippetEditorWindowController: SnippetEditorWindowController?

    /// - Parameters:
    ///   - storeURL: Overrides the default store location. Production uses
    ///     `nil`; tests point at a temporary store so failure paths never touch
    ///     the user's `Yank.store`.
    ///   - makeModelContainer: Store-opening seam, defaulting to `openStore`.
    ///   - presentStartupFailure: Failure-reporting seam, defaulting to the
    ///     alert-and-quit handler.
    init(
        storeURL: URL? = nil,
        makeModelContainer: @escaping ModelContainerFactory = AppCoordinator.openStore,
        presentStartupFailure: @escaping StartupFailurePresenter = AppCoordinator.presentStartupFailureAndQuit
    ) {
        self.storeURL = storeURL
        self.makeModelContainer = makeModelContainer
        self.presentStartupFailure = presentStartupFailure
    }

    /// The production store-opening call, also the default for the injected
    /// factory so tests can drive a real open failure against a temporary store.
    static func openStore(schema: Schema, configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Informs the user and stops. Every Yank feature needs the store, so
    /// staying up would leave a menu bar app that silently does nothing; this
    /// keeps the fail-stop behavior of the previous `fatalError` while giving
    /// the user a readable reason and a guarantee that their data is intact.
    static func presentStartupFailureAndQuit(_ alert: StartupFailureAlert) {
        alert.present()
        NSApplication.shared.terminate(nil)
    }

    func start() {
        let schema = YankSchema.current
        let configuration = makeModelConfiguration(schema: schema)

        let container: ModelContainer
        do {
            container = try makeModelContainer(schema, configuration)
        } catch {
            logger.error("Failed to open the clipboard history store: \(error)")
            presentStartupFailure(StartupFailureAlert(error: error, storeURL: configuration.url))
            return
        }
        modelContainer = container
        hardenStoreFamily()

        // Ask for Accessibility only once the store is open: a startup failure
        // must not request permissions for an app that cannot run.
        checkAccessibility()

        let writer = ClipboardHistoryWriter(modelContainer: container)
        clipboardHistoryWriter = writer

        let monitor = ClipboardMonitor(
            persistSnapshot: { snapshot in await writer.persist(snapshot) }
        )
        monitor.start()
        clipboardMonitor = monitor

        let viewerState = ViewerState()
        let controller = ViewerPanelController(
            modelContainer: container,
            viewerState: viewerState,
            onClearHistory: { [weak self] in
                guard let self else { return }
                try await self.clearHistory()
            },
            onSnippetPaste: { [weak self] snippet in
                self?.handleSnippetPaste(snippet)
            }
        )
        controller.onPaste = { [weak self] item, format in self?.handlePaste(item, format: format) }
        controller.onClose = { [weak self] in self?.panelController?.close() }
        panelController = controller

        snippetEditorWindowController = SnippetEditorWindowController(
            modelContainer: container
        )

        let hotKey = HotKeyManager()
        hotKey.onToggle = { [weak self] in
            self?.panelController?.toggle()
        }
        do {
            try hotKey.register()
        } catch {
            logger.error("Hotkey registration failed: \(error)")
            showHotKeyError(error)
        }
        hotKeyManager = hotKey

        logger.info("Yank initialized successfully")
    }

    private func makeModelConfiguration(schema: Schema) -> ModelConfiguration {
        guard let storeURL else {
            return ModelConfiguration("Yank", schema: schema)
        }
        return ModelConfiguration("Yank", schema: schema, url: storeURL)
    }

    func showSnippetEditor() {
        guard let snippetEditorWindowController else {
            logger.error("Snippet editor requested before app initialization completed")
            return
        }
        snippetEditorWindowController.show()
    }

    func prepareForTermination() -> Bool {
        snippetEditorWindowController?.prepareForTermination() ?? true
    }

    func beginShutdown() {
        clipboardMonitor?.beginShutdown()
        hotKeyManager?.unregister()
    }

    func finishShutdown() async {
        await clipboardMonitor?.finishShutdown()
    }

    private func clearHistory() async throws {
        guard let clipboardMonitor, let clipboardHistoryWriter else { return }
        try await clipboardMonitor.clearHistory {
            try await clipboardHistoryWriter.clearAll()
        }
    }

    // ADR 0003 Stage 1: write → close → simulate (no delay)
    private func handlePaste(_ item: ClipItem, format: PasteFormat) {
        let success: Bool
        switch format {
        case .original:
            success = PasteService.writeToPasteboard(item: item)
        case .plainText:
            success = PasteService.writePlainTextToPasteboard(item: item)
        }
        completePasteWrite(success)
    }

    private func handleSnippetPaste(_ snippet: Snippet) {
        completePasteWrite(PasteService.writeSnippetToPasteboard(snippet: snippet))
    }

    private func completePasteWrite(_ success: Bool) {
        guard success else {
            NSSound.beep()
            logger.error("Failed to write to pasteboard — aborting paste")
            return
        }
        panelController?.close()
        guard AXIsProcessTrusted() else {
            logger.error("Accessibility permission not granted — skipping synthetic paste")
            showAccessibilityError()
            return
        }
        if !PasteService.simulateCmdV() {
            logger.error("Failed to simulate Cmd+V — CGEvent creation or posting failed")
        }
    }

    private func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            logger.warning("Accessibility permission not granted. Paste will not work.")
        }
    }

    private func hardenStoreFamily() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        let report = StoreHardeningService().hardenStoreFamily()
        if report.succeeded {
            logger.debug(
                """
                Store hardening completed: files=\(report.files.count, privacy: .public), \
                fileProtectionUnsupported=\(report.fileProtectionUnsupportedCount, privacy: .public)
                """
            )
        } else {
            logger.error(
                """
                Store hardening completed with failures: \
                files=\(report.files.count, privacy: .public), \
                failures=\(report.failures.count, privacy: .public)
                """
            )
        }
    }

    private func showAccessibilityError() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission required"
        alert.informativeText = """
            Yank needs Accessibility permission to paste automatically. \
            Open System Settings > Privacy & Security > Accessibility, \
            remove Yank, then re-add it. \
            The selected item is on the clipboard — \
            you can paste manually with Cmd+V.
            """
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func showHotKeyError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to register hotkey"
        alert.informativeText = "Cmd+Shift+V could not be registered: \(error)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
