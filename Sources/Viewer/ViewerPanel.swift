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

    // Intercept key events at the window level (before the responder
    // chain), so they are handled even when an internal NSTableView
    // inside the SwiftUI List holds first-responder status.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let action = EmacsKeyHandler.handle(event: event) {
            viewerState.perform(action)
            return
        }
        super.sendEvent(event)
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
        // Sync itemIDs before setting selection so that the first show()
        // (before SwiftUI's onAppear has fired) already has valid data.
        syncItemIDs()
        viewerState.selectedID = viewerState.itemIDs.first
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func syncItemIDs() {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\ClipItem.createdAt, order: .reverse)]
        )
        guard let items = try? context.fetch(descriptor) else { return }
        viewerState.itemIDs = items.map(\.persistentModelID)
    }

    func close() {
        panel?.orderOut(nil)
        NSApp.hide(nil)
        logger.debug("Panel closed, app hidden")
    }
}
