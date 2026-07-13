import AppKit
import SwiftUI
import SwiftData
import os.log

final class ViewerPanel: NSPanel {
    let viewerState: ViewerState
    private let currentUptime: () -> TimeInterval
    /// Tracks modifier keys via flagsChanged events for reliable detection.
    /// NSEvent.modifierFlags on keyDown carries stale state from prior
    /// key combos (Cmd+Shift+V hotkey, Ctrl+N/P navigation).
    private var trackedModifiers: NSEvent.ModifierFlags = []

    init(
        viewerState: ViewerState,
        contentView: NSView,
        currentUptime: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.viewerState = viewerState
        self.currentUptime = currentUptime

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
    // SwiftUI Button rows in the history list can hold first-responder and
    // swallow keyDown, so Emacs bindings must be caught here rather than left
    // to the responder chain.
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
                age: currentUptime() - event.timestamp
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
    typealias HistoryIDLoader = @MainActor () throws -> [PersistentIdentifier]
    typealias LoadFailureReporter = @MainActor (Error) -> Void
    typealias PanelPresenter = @MainActor (ViewerPanel) -> Void

    private static let logger = Logger(
        subsystem: "com.toku345.Yank",
        category: "ViewerPanelController"
    )

    private var panel: ViewerPanel?
    private let modelContainer: ModelContainer
    private let viewerState: ViewerState
    private let clearHistory: @MainActor () async throws -> Void
    private let loadHistoryIDs: HistoryIDLoader
    private let reportLoadFailure: LoadFailureReporter
    private let presentPanel: PanelPresenter

    var onPaste: ((ClipItem, PasteFormat) -> Void)?
    var onClose: (() -> Void)?

    init(
        modelContainer: ModelContainer,
        viewerState: ViewerState,
        onClearHistory: @escaping @MainActor () async throws -> Void,
        loadHistoryIDs: HistoryIDLoader? = nil,
        reportLoadFailure: LoadFailureReporter? = nil,
        presentPanel: PanelPresenter? = nil
    ) {
        self.modelContainer = modelContainer
        self.viewerState = viewerState
        self.clearHistory = onClearHistory
        self.loadHistoryIDs = loadHistoryIDs ?? Self.makeHistoryIDLoader(
            modelContainer: modelContainer
        )
        self.reportLoadFailure = reportLoadFailure ?? Self.reportHistoryLoadFailure
        self.presentPanel = presentPanel ?? Self.presentPanel
    }

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    @discardableResult
    func show() -> Bool {
        let itemIDs: [PersistentIdentifier]
        do {
            itemIDs = try loadHistoryIDs()
        } catch {
            viewerState.clearItems()
            reportLoadFailure(error)
            return false
        }

        viewerState.replaceItems(with: itemIDs)
        viewerState.selectedID = itemIDs.first
        let panel = panelForPresentation()
        panel.resetTrackedModifiers()
        presentPanel(panel)
        return true
    }

    func close() {
        panel?.orderOut(nil)
        NSApp.hide(nil)
        Self.logger.debug("Panel closed, app hidden")
    }

    private func panelForPresentation() -> ViewerPanel {
        if let panel {
            return panel
        }

        let contentView = ViewerContentView(
            viewerState: viewerState,
            onPaste: { [weak self] item, format in self?.onPaste?(item, format) },
            onClose: { [weak self] in self?.onClose?() },
            onClearHistory: { [weak self] in
                guard let self else { return }
                try await self.clearHistory()
            }
        )
        let hostingView = NSHostingView(
            rootView: contentView.modelContainer(modelContainer)
        )
        let newPanel = ViewerPanel(
            viewerState: viewerState,
            contentView: hostingView
        )
        panel = newPanel
        return newPanel
    }

    private static func makeHistoryIDLoader(
        modelContainer: ModelContainer
    ) -> HistoryIDLoader {
        {
            try loadSavedHistoryIDs(from: modelContainer)
        }
    }

    static func loadSavedHistoryIDs(
        from modelContainer: ModelContainer
    ) throws -> [PersistentIdentifier] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<ClipItem>(
            sortBy: [SortDescriptor(\ClipItem.createdAt, order: .reverse)]
        )
        descriptor.includePendingChanges = false
        return try context.fetchIdentifiers(descriptor)
    }

    private static func reportHistoryLoadFailure(_ error: Error) {
        logger.error(
            """
            Failed to load clipboard history identifiers; \
            errorType=\(String(reflecting: type(of: error)), privacy: .public); \
            error=\(error.localizedDescription, privacy: .private)
            """
        )
        let alert = NSAlert()
        alert.messageText = "Could not open clipboard history"
        alert.informativeText = """
            Yank could not load saved clipboard history, so the viewer was not opened. \
            Your saved history was not changed. \
            \(error.localizedDescription)
            """
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func presentPanel(_ panel: ViewerPanel) {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
