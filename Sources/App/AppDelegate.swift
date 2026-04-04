import AppKit
import SwiftData
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "AppDelegate")

    var modelContainer: ModelContainer!
    var clipboardMonitor: ClipboardMonitor!
    var hotKeyManager: HotKeyManager!
    var panelController: ViewerPanelController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let schema = Schema([ClipItem.self, Snippet.self, SnippetFolder.self])
        let config = ModelConfiguration("Yank", schema: schema)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            logger.error("Failed to create ModelContainer: \(error)")
            fatalError("Failed to create ModelContainer: \(error)")
        }

        let context = ModelContext(modelContainer)

        clipboardMonitor = ClipboardMonitor(modelContext: context)
        clipboardMonitor.start()

        panelController = ViewerPanelController(modelContext: context, monitor: clipboardMonitor)

        hotKeyManager = HotKeyManager()
        hotKeyManager.onToggle = { [weak self] in
            self?.panelController.toggle()
        }
        hotKeyManager.register()

        logger.info("Yank initialized successfully")
    }

    func shutdown() {
        clipboardMonitor?.stop()
        hotKeyManager?.unregister()
    }
}
