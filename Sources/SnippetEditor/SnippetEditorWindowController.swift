import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import os.log

@MainActor
final class SnippetEditorWindowController: NSObject, NSWindowDelegate {
    typealias DirtyDraftPrompt = @MainActor () -> DirtyDraftDecision
    typealias DeleteConfirmation = @MainActor (_ title: String, _ message: String) -> Bool
    typealias ErrorReporter = @MainActor (_ operation: String, _ error: Error) -> Void
    typealias XMLFilePicker = @MainActor () -> URL?
    typealias WindowFactory = @MainActor (_ contentView: NSView) -> NSWindow
    typealias WindowPresenter = @MainActor (_ window: NSWindow) -> Void

    private static let logger = Logger(
        subsystem: "com.toku345.Yank",
        category: "SnippetEditor"
    )

    private let modelContainer: ModelContainer
    private let state: SnippetEditorState
    private let dragRegistry = SnippetEditorDragRegistry()
    private let dirtyDraftPrompt: DirtyDraftPrompt
    private let deleteConfirmation: DeleteConfirmation
    private let errorReporter: ErrorReporter
    private let xmlFilePicker: XMLFilePicker
    private let windowFactory: WindowFactory
    private let windowPresenter: WindowPresenter

    private(set) var window: NSWindow?

    init(
        modelContainer: ModelContainer,
        state: SnippetEditorState? = nil,
        dirtyDraftPrompt: DirtyDraftPrompt? = nil,
        deleteConfirmation: DeleteConfirmation? = nil,
        errorReporter: ErrorReporter? = nil,
        xmlFilePicker: XMLFilePicker? = nil,
        windowFactory: WindowFactory? = nil,
        windowPresenter: WindowPresenter? = nil
    ) {
        self.modelContainer = modelContainer
        self.state = state ?? SnippetEditorState()
        self.dirtyDraftPrompt = dirtyDraftPrompt ?? Self.promptForDirtyDraft
        self.deleteConfirmation = deleteConfirmation ?? Self.confirmDeletion
        self.errorReporter = errorReporter ?? Self.reportError
        self.xmlFilePicker = xmlFilePicker ?? Self.pickXMLFile
        self.windowFactory = windowFactory ?? Self.makeWindow
        self.windowPresenter = windowPresenter ?? Self.presentWindow
    }

    @discardableResult
    func show() -> Bool {
        do {
            state.synchronize(with: try SnippetMutations.loadFolders(in: modelContainer.mainContext))
        } catch {
            errorReporter("open the snippet editor", error)
            return false
        }
        let window = windowForPresentation()
        windowPresenter(window)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        prepareForTermination()
    }

    func prepareForTermination() -> Bool {
        do {
            return try state.resolveDirtyDraft(
                decisionProvider: dirtyDraftPrompt,
                in: modelContainer.mainContext
            )
        } catch {
            errorReporter("save the snippet", error)
            return false
        }
    }

    private func windowForPresentation() -> NSWindow {
        if let window {
            return window
        }

        let rootView = SnippetEditorView(
            state: state,
            dirtyDraftPrompt: dirtyDraftPrompt,
            deleteConfirmation: deleteConfirmation,
            errorReporter: errorReporter,
            xmlFilePicker: xmlFilePicker,
            dragRegistry: dragRegistry
        )
        .modelContainer(modelContainer)
        let hostingView = NSHostingView(rootView: rootView)
        let newWindow = windowFactory(hostingView)
        newWindow.delegate = self
        window = newWindow
        return newWindow
    }

    private static func makeWindow(contentView: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.title = "Snippets"
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        let frameName = "SnippetEditorWindow"
        if !window.setFrameUsingName(frameName) {
            window.center()
        }
        window.setFrameAutosaveName(frameName)
        return window
    }

    private static func presentWindow(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private static func promptForDirtyDraft() -> DirtyDraftDecision {
        let alert = NSAlert()
        alert.messageText = "Save changes to this snippet?"
        alert.informativeText = "Your changes will be lost if you discard them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private static func confirmDeletion(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func reportError(operation: String, error: Error) {
        logger.error(
            """
            Failed to \(operation, privacy: .public); \
            errorType=\(String(reflecting: type(of: error)), privacy: .public)
            """
        )
        let alert = NSAlert()
        alert.messageText = "Could not \(operation)"
        alert.informativeText = "Your previous snippet data was preserved. \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func pickXMLFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import Clipy Snippets"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func importClipyXML(
        from url: URL,
        state: SnippetEditorState,
        context: ModelContext,
        saveChanges: SnippetMutations.SaveChanges = { try $0.save() }
    ) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ClipySnippetXMLParserError.readFailed
        }
        let imported = try ClipySnippetXMLParser.parse(data: data)
        let result = try SnippetMutations.importClipyFolders(
            imported,
            in: context,
            saveChanges: saveChanges
        )
        if !imported.isEmpty {
            try state.apply(result, in: context)
        }
    }
}
