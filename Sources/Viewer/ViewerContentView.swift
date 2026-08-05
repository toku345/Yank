import AppKit
import SwiftData
import SwiftUI
import os.log

struct ViewerContentView: View {
    private static let logger = Logger(
        subsystem: "com.toku345.Yank", category: "ViewerContentView"
    )

    @Environment(\.modelContext)
    private var modelContext

    @Query(sort: \ClipItem.createdAt, order: .reverse)
    private var clipItems: [ClipItem]

    @Query(sort: \SnippetFolder.sortOrder)
    private var snippetFolders: [SnippetFolder]

    @Bindable var viewerState: ViewerState
    @State private var isClearingHistory = false

    let onPaste: (ClipItem, PasteFormat) -> Void
    let onClose: () -> Void
    let onClearHistory: @MainActor () async throws -> Void

    var body: some View {
        TabView(selection: $viewerState.selectedTab) {
            Tab("History", systemImage: "clock", value: ViewerTab.history) {
                historyContent
            }
            Tab("Snippets", systemImage: "text.quote", value: ViewerTab.snippets) {
                snippetContent
            }
        }
        .frame(minWidth: 350, idealWidth: 400, minHeight: 300, idealHeight: 500)
        .onChange(of: viewerState.pendingAction) { _, action in
            guard let action else { return }
            defer { viewerState.pendingAction = nil }
            handleViewAction(action)
        }
        .onChange(of: clipItems.map(\.persistentModelID)) { _, newIDs in
            viewerState.replaceHistoryItems(with: newIDs)
        }
        .task(id: selectableSnippetIDs) { [snippetIDs = selectableSnippetIDs] in
            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            viewerState.replaceSnippets(with: snippetIDs)
        }
    }

    private var selectableSnippetIDs: [PersistentIdentifier] {
        SnippetCollectionProjection.selectableSnippetIDs(
            from: SnippetCollectionProjection.snapshots(from: snippetFolders)
        )
    }

    @ViewBuilder
    private var snippetContent: some View {
        if snippetFolders.isEmpty {
            ContentUnavailableView(
                "No Snippets",
                systemImage: "text.quote",
                description: Text("Create a snippet in Manage Snippets to see it here")
            )
        } else {
            SnippetListView(
                folders: snippetFolders,
                viewerState: viewerState,
                onSnippetTap: nil
            )
        }
    }

    private var historyContent: some View {
        VStack(spacing: 0) {
            if clipItems.isEmpty {
                ContentUnavailableView(
                    "No Clipboard History",
                    systemImage: "clipboard",
                    description: Text("Copy something to see it here")
                )
            } else {
                HistoryListView(
                    items: clipItems,
                    viewerState: viewerState,
                    onItemTap: { item in
                        onPaste(item, .original)
                    }
                )
            }
            Divider()
            HistoryControls(
                viewerState: viewerState,
                hasItems: !clipItems.isEmpty,
                isClearingHistory: isClearingHistory
            )
        }
    }

    private struct HistoryControls: View {
        @Bindable var viewerState: ViewerState
        let hasItems: Bool
        let isClearingHistory: Bool

        var body: some View {
            HStack {
                Button("Delete Selected") {
                    viewerState.perform(.deleteSelected)
                }
                .disabled(viewerState.selectedHistoryID == nil || isClearingHistory)

                Spacer()

                Button("Clear All", role: .destructive) {
                    viewerState.perform(.clearHistory)
                }
                .disabled(!hasItems || isClearingHistory)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func handleViewAction(_ action: ViewerAction) {
        ViewerContentActionRouting.handle(
            action: action,
            selectedTab: viewerState.selectedTab,
            onClose: onClose,
            onHistoryAction: handleHistoryAction
        )
    }

    private func handleHistoryAction(_ action: ViewerAction) {
        switch action {
        case .paste(let format):
            if let id = viewerState.selectedHistoryID,
               let item = clipItems.first(where: { $0.persistentModelID == id }) {
                onPaste(item, format)
            }
        case .deleteSelected:
            deleteSelectedItem()
        case .clearHistory:
            beginClearingHistory()
        case .move, .jumpToStart, .jumpToEnd, .switchTab, .close:
            break
        }
    }

    private func deleteSelectedItem() {
        guard !isClearingHistory else { return }
        do {
            let result = try HistoryDeletion.deleteSelectedItem(
                from: clipItems,
                in: modelContext,
                viewerState: viewerState
            )
            if case .selectedItemMissing(let id) = result {
                Self.logger.warning(
                    "Delete skipped because selected item was missing: \(String(describing: id), privacy: .public)"
                )
            }
        } catch {
            reportDeletionFailure(operation: "delete the selected item", error: error)
        }
    }

    private func beginClearingHistory() {
        guard !isClearingHistory, confirmClearAll() else { return }
        isClearingHistory = true
        Task { @MainActor in
            defer { isClearingHistory = false }
            do {
                try await onClearHistory()
                viewerState.clearHistoryItems()
            } catch {
                reportDeletionFailure(operation: "clear clipboard history", error: error)
            }
        }
    }

    private func confirmClearAll() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = """
            This permanently deletes all saved clipboard history and cannot be undone. \
            Your current system clipboard contents are not affected.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func reportDeletionFailure(operation: String, error: Error) {
        Self.logger.error(
            """
            Failed to \(operation, privacy: .public); \
            selectedID=\(String(describing: viewerState.selectedHistoryID), privacy: .public); \
            itemCount=\(clipItems.count, privacy: .public); \
            errorType=\(String(reflecting: type(of: error)), privacy: .public); \
            error=\(error.localizedDescription, privacy: .public)
            """
        )
        let alert = NSAlert()
        alert.messageText = "Could not \(operation)"
        alert.informativeText = """
            Saving the change to clipboard history failed, so nothing was deleted. \
            \(error.localizedDescription)
            """
        alert.alertStyle = .warning
        alert.runModal()
    }
}

enum ViewerContentActionRouting {
    static func handle(
        action: ViewerAction,
        selectedTab: ViewerTab,
        onClose: () -> Void,
        onHistoryAction: (ViewerAction) -> Void
    ) {
        if action == .close {
            onClose()
            return
        }
        guard selectedTab == .history else { return }

        switch action {
        case .paste, .deleteSelected, .clearHistory:
            onHistoryAction(action)
        case .move, .jumpToStart, .jumpToEnd, .switchTab, .close:
            break
        }
    }
}

@MainActor
enum HistoryDeletion {
    typealias SaveChanges = (ModelContext) throws -> Void

    enum DeleteSelectedResult: Equatable {
        case deleted
        case noSelection
        case selectedItemMissing(PersistentIdentifier)
    }

    static func deleteSelectedItem(
        from items: [ClipItem],
        in modelContext: ModelContext,
        viewerState: ViewerState,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws -> DeleteSelectedResult {
        guard let selectedID = viewerState.selectedHistoryID else {
            viewerState.replaceHistoryItems(with: items.map(\.persistentModelID))
            return .noSelection
        }

        guard let item = items.first(where: { $0.persistentModelID == selectedID }) else {
            viewerState.replaceHistoryItems(with: items.map(\.persistentModelID))
            return .selectedItemMissing(selectedID)
        }

        modelContext.delete(item)
        try saveOrRollback(in: modelContext, saveChanges: saveChanges)
        viewerState.removeHistoryItem(id: selectedID)
        return .deleted
    }

    private static func saveOrRollback(
        in modelContext: ModelContext,
        saveChanges: SaveChanges
    ) throws {
        do {
            try saveChanges(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
