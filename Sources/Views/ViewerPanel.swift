import AppKit
import SwiftUI
import SwiftData
import os.log

final class ViewerPanel: NSPanel {
    let keyboardState: KeyboardState

    init(keyboardState: KeyboardState, contentView: NSView) {
        self.keyboardState = keyboardState

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
        self.isFloatingPanel = true
        self.level = .floating
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.title = "Yank"
        self.becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !EmacsKeyHandler.handle(event: event, state: keyboardState) {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class ViewerPanelController {
    private var panel: ViewerPanel?
    private let modelContext: ModelContext
    private let monitor: ClipboardMonitor
    private let keyboardState = KeyboardState()
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "ViewerPanelController")
    /// The app that was frontmost before showing the panel (paste target)
    private var previousApp: NSRunningApplication?

    init(modelContext: ModelContext, monitor: ClipboardMonitor) {
        self.modelContext = modelContext
        self.monitor = monitor
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        logger.debug("Previous app: \(self.previousApp?.localizedName ?? "nil", privacy: .public)")

        if panel == nil {
            let contentView = ViewerContentView(
                keyboardState: keyboardState,
                onPaste: { [weak self] item in self?.pasteAndClose(item) },
                onClose: { [weak self] in self?.close() }
            )
            let hostingView = NSHostingView(
                rootView: contentView.modelContext(modelContext)
            )
            panel = ViewerPanel(keyboardState: keyboardState, contentView: hostingView)
        }
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.orderOut(nil)
        // Hiding an LSUIElement app reliably returns focus to the previous app
        NSApp.hide(nil)
        logger.debug("Panel closed, app hidden")
    }

    private func pasteAndClose(_ item: ClipItem) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            PasteEngine.paste(item: item, monitor: self.monitor)
        }
    }
}
