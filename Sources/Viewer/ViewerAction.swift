import Foundation
import SwiftData

enum PasteFormat {
    case original
    case plainText
}

enum ViewerAction: Equatable {
    enum Direction {
        case up, down
    }

    case move(Direction)
    case jumpToStart
    case jumpToEnd
    case paste(PasteFormat)
    case close
}

@Observable
@MainActor
final class ViewerState {
    /// View-coordinating actions only (paste, close).
    /// Movement actions are handled synchronously via perform().
    var pendingAction: ViewerAction?

    var selectedID: PersistentIdentifier?
    var itemIDs: [PersistentIdentifier] = []

    func perform(_ action: ViewerAction) {
        switch action {
        case .move(let direction):
            moveSelection(direction)
        case .jumpToStart:
            selectedID = itemIDs.first
        case .jumpToEnd:
            selectedID = itemIDs.last
        case .paste, .close:
            pendingAction = action
        }
    }

    private func moveSelection(_ direction: ViewerAction.Direction) {
        guard !itemIDs.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in
            itemIDs.firstIndex(of: id)
        } ?? -1
        switch direction {
        case .down:
            let newIndex = min(currentIndex + 1, itemIDs.count - 1)
            selectedID = itemIDs[newIndex]
        case .up:
            let newIndex = max(currentIndex - 1, 0)
            selectedID = itemIDs[newIndex]
        }
    }
}
