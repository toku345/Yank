import AppKit
import SwiftData
import os.log

@MainActor
final class AppCoordinator {
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "AppCoordinator")
    private let createModelContainer: () throws -> ModelContainer
    private let presentStoreError: (NSAlert) -> Void
    private let terminate: () -> Void

    private(set) var modelContainer: ModelContainer?
    private(set) var clipboardHistoryWriter: ClipboardHistoryWriter?
    private(set) var clipboardMonitor: ClipboardMonitor?
    private(set) var hotKeyManager: HotKeyManager?
    private(set) var panelController: ViewerPanelController?
    private(set) var snippetEditorWindowController: SnippetEditorWindowController?

    init(
        createModelContainer: @escaping () throws -> ModelContainer = AppCoordinator.createPersistentContainer,
        presentStoreError: @escaping (NSAlert) -> Void = { $0.runModal() },
        terminate: @escaping () -> Void = { NSApplication.shared.terminate(nil) }
    ) {
        self.createModelContainer = createModelContainer
        self.presentStoreError = presentStoreError
        self.terminate = terminate
    }

    func start() {
        let container: ModelContainer
        do {
            container = try createModelContainer()
        } catch {
            logger.error("Failed to create ModelContainer: \(error)")
            presentStoreError(Self.makeStoreErrorAlert())
            terminate()
            return
        }
        modelContainer = container
        hardenStoreFamily()
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

    private static func createPersistentContainer() throws -> ModelContainer {
        let schema = YankSchema.current
        let config = ModelConfiguration("Yank", schema: schema)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func makeStoreErrorAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Yank could not open its data store"
        alert.informativeText = """
            The clipboard history and snippet store could not be opened. \
            A data migration may have failed. \
            Yank has left the existing store intact and will quit without deleting or recreating it. \
            Keep the store files and report this problem before trying to recover your data.
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        return alert
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
