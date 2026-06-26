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
    case deleteSelected
    case clearHistory
    case close
}

@Observable
@MainActor
final class ViewerState {
    /// View-coordinating actions that require view/environment side effects.
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
        case .paste, .deleteSelected, .clearHistory, .close:
            pendingAction = action
        }
    }

    func replaceItems(with newIDs: [PersistentIdentifier]) {
        itemIDs = newIDs
        guard !newIDs.isEmpty else {
            selectedID = nil
            return
        }
        if let selectedID, newIDs.contains(selectedID) {
            return
        }
        selectedID = newIDs.first
    }

    func removeItem(id: PersistentIdentifier) {
        guard let removedIndex = itemIDs.firstIndex(of: id) else {
            replaceItems(with: itemIDs)
            return
        }

        let newIDs = itemIDs.filter { $0 != id }
        itemIDs = newIDs
        guard !newIDs.isEmpty else {
            selectedID = nil
            return
        }
        selectedID = newIDs[min(removedIndex, newIDs.count - 1)]
    }

    func clearItems() {
        itemIDs = []
        selectedID = nil
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
