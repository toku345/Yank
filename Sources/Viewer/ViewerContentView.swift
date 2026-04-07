import SwiftData
import SwiftUI

struct ViewerContentView: View {
    @Query(sort: \ClipItem.createdAt, order: .reverse)
    private var clipItems: [ClipItem]

    @Bindable var viewerState: ViewerState

    let onPaste: (ClipItem) -> Void
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
                        onPaste(item)
                    }
                )
            }
        }
        .frame(minWidth: 350, idealWidth: 400, minHeight: 300, idealHeight: 500)
        .onChange(of: viewerState.pendingAction) { _, action in
            guard let action else { return }
            defer { viewerState.pendingAction = nil }
            handleViewAction(action)
        }
        .onChange(of: clipItems.map(\.persistentModelID)) { _, newIDs in
            viewerState.itemIDs = newIDs
            if viewerState.selectedID == nil, let first = newIDs.first {
                viewerState.selectedID = first
            }
        }
        .onAppear {
            viewerState.itemIDs = clipItems.map(\.persistentModelID)
            if viewerState.selectedID == nil, let first = clipItems.first {
                viewerState.selectedID = first.persistentModelID
            }
        }
    }

    private func handleViewAction(_ action: ViewerAction) {
        switch action {
        case .paste:
            if let id = viewerState.selectedID,
               let item = clipItems.first(where: { $0.persistentModelID == id }) {
                onPaste(item)
            }
        case .close:
            onClose()
        case .move, .jumpToStart, .jumpToEnd:
            break
        }
    }
}
