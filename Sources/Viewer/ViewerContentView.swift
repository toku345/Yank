import SwiftData
import SwiftUI

struct ViewerContentView: View {
    @Query(sort: \ClipItem.createdAt, order: .reverse)
    private var clipItems: [ClipItem]

    let viewerState: ViewerState
    @State private var selectedID: PersistentIdentifier?

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
                    selectedID: $selectedID
                )
            }
        }
        .frame(minWidth: 350, idealWidth: 400, minHeight: 300, idealHeight: 500)
        .onChange(of: viewerState.pendingAction) { _, action in
            guard let action else { return }
            defer { viewerState.pendingAction = nil }
            handleAction(action)
        }
        .onAppear {
            if let first = clipItems.first, selectedID == nil {
                selectedID = first.persistentModelID
            }
        }
        .onChange(of: clipItems.first?.persistentModelID) {
            if selectedID == nil, let first = clipItems.first {
                selectedID = first.persistentModelID
            }
        }
    }

    private func handleAction(_ action: ViewerAction) {
        switch action {
        case .move(let direction):
            moveSelection(direction)
        case .jumpToStart:
            guard let first = clipItems.first else { return }
            selectedID = first.persistentModelID
        case .jumpToEnd:
            guard let last = clipItems.last else { return }
            selectedID = last.persistentModelID
        case .paste:
            if let id = selectedID, let item = clipItems.first(where: { $0.persistentModelID == id }) {
                onPaste(item)
            }
        case .close:
            onClose()
        }
    }

    private func moveSelection(_ direction: ViewerAction.Direction) {
        guard !clipItems.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in
            clipItems.firstIndex(where: { $0.persistentModelID == id })
        } ?? -1
        switch direction {
        case .down:
            let newIndex = min(currentIndex + 1, clipItems.count - 1)
            selectedID = clipItems[newIndex].persistentModelID
        case .up:
            let newIndex = max(currentIndex - 1, 0)
            selectedID = clipItems[newIndex].persistentModelID
        }
    }
}
