import AppKit
import SwiftData
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "AppDelegate")

    private(set) var modelContainer: ModelContainer?
    private(set) var clipboardMonitor: ClipboardMonitor?
    private(set) var hotKeyManager: HotKeyManager?
    private(set) var panelController: ViewerPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let schema = Schema([ClipItem.self, Snippet.self, SnippetFolder.self])
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

        panelController = ViewerPanelController(modelContext: context, monitor: monitor)

        let hotKey = HotKeyManager()
        hotKey.onToggle = { [weak self] in
            self?.panelController?.toggle()
        }
        hotKey.register()
        hotKeyManager = hotKey

        logger.info("Yank initialized successfully")
    }

    func shutdown() {
        clipboardMonitor?.stop()
        hotKeyManager?.unregister()
    }
}
