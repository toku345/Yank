import SwiftUI
import SwiftData

struct ViewerContentView: View {
    @Query(sort: \ClipItem.createdAt, order: .reverse)
    private var clipItems: [ClipItem]

    @ObservedObject var keyboardState: KeyboardState
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
                    selectedIndex: $selectedIndex,
                    onPaste: onPaste
                )
            }
        }
        .frame(minWidth: 350, idealWidth: 400, minHeight: 300, idealHeight: 500)
        .onChange(of: keyboardState.moveDirection) { _, direction in
            guard let direction else { return }
            moveSelection(direction)
            keyboardState.moveDirection = nil
        }
        .onChange(of: keyboardState.shouldJumpToStart) { _, jump in
            guard jump, !clipItems.isEmpty else { return }
            selectedIndex = 0
            keyboardState.shouldJumpToStart = false
        }
        .onChange(of: keyboardState.shouldJumpToEnd) { _, jump in
            guard jump, !clipItems.isEmpty else { return }
            selectedIndex = clipItems.count - 1
            keyboardState.shouldJumpToEnd = false
        }
        .onChange(of: keyboardState.shouldPaste) { _, paste in
            guard paste else { return }
            if let idx = selectedIndex, idx < clipItems.count {
                onPaste(clipItems[idx])
            }
            keyboardState.shouldPaste = false
        }
        .onChange(of: keyboardState.shouldClose) { _, close in
            guard close else { return }
            onClose()
            keyboardState.shouldClose = false
        }
        .onAppear {
            if !clipItems.isEmpty && selectedIndex == nil {
                selectedIndex = 0
            }
        }
    }

    private func moveSelection(_ direction: KeyboardState.MoveDirection) {
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
