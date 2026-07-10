import AppKit
import SwiftUI
import SwiftData
import os.log

final class ViewerPanel: NSPanel {
    let viewerState: ViewerState
    /// Tracks modifier keys via flagsChanged events for reliable detection.
    /// NSEvent.modifierFlags on keyDown carries stale state from prior
    /// key combos (Cmd+Shift+V hotkey, Ctrl+N/P navigation).
    private var trackedModifiers: NSEvent.ModifierFlags = []

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

    // Intercept key events at the window level before the responder chain.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            trackedModifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
        }
        if event.type == .keyDown,
           let action = EmacsKeyHandler.handle(
               event: event, trackedModifiers: trackedModifiers
           ) {
            guard ViewerActionDispatchPolicy.shouldDispatch(
                action: action,
                isRepeat: event.isARepeat,
                eventTimestamp: event.timestamp,
                currentTimestamp: ProcessInfo.processInfo.systemUptime
            ) else { return }
            viewerState.perform(action)
            return
        }
        super.sendEvent(event)
    }

    func resetTrackedModifiers() {
        trackedModifiers = []
    }
}

@MainActor
final class ViewerPanelController {
    private var panel: ViewerPanel?
    private let modelContainer: ModelContainer
    private let viewerState: ViewerState
    private let logger = Logger(subsystem: "com.toku345.Yank", category: "ViewerPanelController")

    var onPaste: ((ClipItem, PasteFormat) -> Void)?
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
                onPaste: { [weak self] item, format in self?.onPaste?(item, format) },
                onClose: { [weak self] in self?.onClose?() }
            )
            let hostingView = NSHostingView(
                rootView: contentView.modelContainer(modelContainer)
            )
            panel = ViewerPanel(viewerState: viewerState, contentView: hostingView)
        }
        // Query updates own item synchronization. Reopening starts at the top.
        viewerState.selectedID = viewerState.itemIDs.first
        // Clear stale modifier state from the Cmd+Shift+V hotkey
        panel?.resetTrackedModifiers()
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
