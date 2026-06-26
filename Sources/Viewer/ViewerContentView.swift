import AppKit
import SwiftData
import SwiftUI

struct ViewerContentView: View {
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
                _ = try HistoryDeletion.deleteSelectedItem(
                    from: clipItems,
                    in: modelContext,
                    viewerState: viewerState
                )
            } catch {
                NSSound.beep()
            }
        case .clearHistory:
            do {
                try HistoryDeletion.clearAll(
                    items: clipItems,
                    in: modelContext,
                    viewerState: viewerState
                )
            } catch {
                NSSound.beep()
            }
        case .close:
            onClose()
        case .move, .jumpToStart, .jumpToEnd:
            break
        }
    }
}

@MainActor
enum HistoryDeletion {
    @discardableResult
    static func deleteSelectedItem(
        from items: [ClipItem],
        in modelContext: ModelContext,
        viewerState: ViewerState
    ) throws -> Bool {
        guard let selectedID = viewerState.selectedID,
              let item = items.first(where: { $0.persistentModelID == selectedID }) else {
            viewerState.replaceItems(with: items.map(\.persistentModelID))
            return false
        }

        modelContext.delete(item)
        try modelContext.save()
        viewerState.removeItem(id: selectedID)
        return true
    }

    static func clearAll(
        items: [ClipItem],
        in modelContext: ModelContext,
        viewerState: ViewerState
    ) throws {
        for item in items {
            modelContext.delete(item)
        }
        try modelContext.save()
        viewerState.clearItems()
    }
}
