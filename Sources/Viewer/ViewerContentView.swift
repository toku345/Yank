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

    @Bindable var viewerState: ViewerState

    let onPaste: (ClipItem, PasteFormat) -> Void
    let onClose: () -> Void

    var body: some View {
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
                    selectedID: $viewerState.selectedID,
                    onItemTap: { item in
                        onPaste(item, .original)
                    }
                )
            }
            Divider()
            historyControls
        }
        .frame(minWidth: 350, idealWidth: 400, minHeight: 300, idealHeight: 500)
        .onChange(of: viewerState.pendingAction) { _, action in
            guard let action else { return }
            defer { viewerState.pendingAction = nil }
            handleViewAction(action)
        }
        .onChange(of: clipItems.map(\.persistentModelID)) { _, newIDs in
            viewerState.replaceItems(with: newIDs)
        }
        .onAppear {
            viewerState.replaceItems(with: clipItems.map(\.persistentModelID))
        }
    }

    private var historyControls: some View {
        HStack {
            Button("Delete Selected") {
                viewerState.perform(.deleteSelected)
            }
            .disabled(viewerState.selectedID == nil)

            Spacer()

            Button("Clear All", role: .destructive) {
                viewerState.perform(.clearHistory)
            }
            .disabled(clipItems.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func handleViewAction(_ action: ViewerAction) {
        switch action {
        case .paste(let format):
            if let id = viewerState.selectedID,
               let item = clipItems.first(where: { $0.persistentModelID == id }) {
                onPaste(item, format)
            }
        case .deleteSelected:
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
        case .clearHistory:
            do {
                _ = try HistoryDeletion.clearAllIfConfirmed(
                    items: clipItems,
                    in: modelContext,
                    viewerState: viewerState,
                    confirmClearAll: { confirmClearAll() }
                )
            } catch {
                reportDeletionFailure(operation: "clear clipboard history", error: error)
            }
        case .close:
            onClose()
        case .move, .jumpToStart, .jumpToEnd:
            break
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
            selectedID=\(String(describing: viewerState.selectedID), privacy: .public); \
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
        guard let selectedID = viewerState.selectedID else {
            viewerState.replaceItems(with: items.map(\.persistentModelID))
            return .noSelection
        }

        guard let item = items.first(where: { $0.persistentModelID == selectedID }) else {
            viewerState.replaceItems(with: items.map(\.persistentModelID))
            return .selectedItemMissing(selectedID)
        }

        modelContext.delete(item)
        try saveOrRollback(in: modelContext, saveChanges: saveChanges)
        viewerState.removeItem(id: selectedID)
        return .deleted
    }

    @discardableResult
    static func clearAllIfConfirmed(
        items: [ClipItem],
        in modelContext: ModelContext,
        viewerState: ViewerState,
        confirmClearAll: () -> Bool,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws -> Bool {
        guard confirmClearAll() else { return false }
        try clearAll(
            items: items,
            in: modelContext,
            viewerState: viewerState,
            saveChanges: saveChanges
        )
        return true
    }

    private static func clearAll(
        items: [ClipItem],
        in modelContext: ModelContext,
        viewerState: ViewerState,
        saveChanges: SaveChanges = { try $0.save() }
    ) throws {
        for item in items {
            modelContext.delete(item)
        }
        try saveOrRollback(in: modelContext, saveChanges: saveChanges)
        viewerState.clearItems()
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
