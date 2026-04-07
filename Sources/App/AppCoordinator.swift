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

        let context = ModelContext(container)

        let monitor = ClipboardMonitor(modelContext: context)
        monitor.start()
        clipboardMonitor = monitor

        let viewerState = ViewerState()
        let controller = ViewerPanelController(
            modelContainer: container,
            viewerState: viewerState
        )
        controller.onPaste = { [weak self] item in self?.handlePaste(item) }
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
    private func handlePaste(_ item: ClipItem) {
        guard PasteService.writeToPasteboard(item: item) else {
            logger.error("Failed to write to pasteboard — aborting paste")
            return
        }
        panelController?.close()
        if !PasteService.simulateCmdV() {
            logger.error("Paste failed — Accessibility permission may not be granted")
        }
    }

    private func checkAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            logger.warning("Accessibility permission not granted. Paste will not work.")
        }
    }

    private func showHotKeyError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to register hotkey"
        alert.informativeText = "Cmd+Shift+V could not be registered: \(error)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
