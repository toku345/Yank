import SwiftUI
import SwiftData

struct ViewerContentView: View {
    @Query(sort: \ClipItem.createdAt, order: .reverse)
    private var clipItems: [ClipItem]

    let viewerState: ViewerState
    @State private var selectedIndex: Int?

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
                    selectedIndex: $selectedIndex
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
            if !clipItems.isEmpty && selectedIndex == nil {
                selectedIndex = 0
            }
        }
    }

    private func handleAction(_ action: ViewerAction) {
        switch action {
        case .move(let direction):
            moveSelection(direction)
        case .jumpToStart:
            guard !clipItems.isEmpty else { return }
            selectedIndex = 0
        case .jumpToEnd:
            guard !clipItems.isEmpty else { return }
            selectedIndex = clipItems.count - 1
        case .paste:
            if let idx = selectedIndex, idx < clipItems.count {
                onPaste(clipItems[idx])
            }
        case .close:
            onClose()
        }
    }

    private func moveSelection(_ direction: ViewerAction.Direction) {
        guard !clipItems.isEmpty else { return }
        let current = selectedIndex ?? -1
        switch direction {
        case .down:
            selectedIndex = min(current + 1, clipItems.count - 1)
        case .up:
            selectedIndex = max(current - 1, 0)
        }
    }
}
