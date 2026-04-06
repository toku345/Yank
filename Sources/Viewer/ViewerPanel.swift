import AppKit
import SwiftUI
import SwiftData
import os.log

final class ViewerPanel: NSPanel {
    let viewerState: ViewerState

    init(viewerState: ViewerState, contentView: NSView) {
        self.viewerState = viewerState

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
        if let action = EmacsKeyHandler.handle(event: event) {
            viewerState.pendingAction = action
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class ViewerPanelController {
    private var panel: ViewerPanel?
    private let modelContainer: ModelContainer
    private let viewerState: ViewerState
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "ViewerPanelController")

    var onPaste: ((ClipItem) -> Void)?
    var onClose: (() -> Void)?

    init(modelContainer: ModelContainer, viewerState: ViewerState) {
        self.modelContainer = modelContainer
        self.viewerState = viewerState
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let contentView = ViewerContentView(
                viewerState: viewerState,
                onPaste: { [weak self] item in self?.onPaste?(item) },
                onClose: { [weak self] in self?.onClose?() }
            )
            let hostingView = NSHostingView(
                rootView: contentView.modelContainer(modelContainer)
            )
            panel = ViewerPanel(viewerState: viewerState, contentView: hostingView)
        }
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func close() {
        panel?.orderOut(nil)
        NSApp.hide(nil)
        logger.debug("Panel closed, app hidden")
    }
}
