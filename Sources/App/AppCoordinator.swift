import AppKit
import SwiftData
import os.log

@MainActor
final class AppCoordinator {
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "AppCoordinator")

    private(set) var modelContainer: ModelContainer?
    private(set) var clipboardMonitor: ClipboardMonitor?
    private(set) var hotKeyManager: HotKeyManager?
    private(set) var panelController: ViewerPanelController?

    func start() {
        checkAccessibility()

        let schema = Schema([ClipItem.self])
        let config = ModelConfiguration("Yank", schema: schema)

        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            logger.error("Failed to create ModelContainer: \(error)")
            fatalError("Failed to create ModelContainer: \(error)")
        }
        modelContainer = container
        hardenStoreFamily()

        let monitor = ClipboardMonitor(modelContainer: container)
        monitor.start()
        clipboardMonitor = monitor

        let viewerState = ViewerState()
        let controller = ViewerPanelController(
            modelContainer: container,
            viewerState: viewerState
        )
        controller.onPaste = { [weak self] item, format in self?.handlePaste(item, format: format) }
        controller.onClose = { [weak self] in self?.panelController?.close() }
        panelController = controller

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

    func shutdown() {
        clipboardMonitor?.stop()
        hotKeyManager?.unregister()
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
        guard success else {
            // Plain-text paste can fail when the item has no text representation
            // (e.g. image-only clips). Beep to signal the action didn't take.
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
