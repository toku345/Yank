import Foundation
import SwiftData

enum PasteFormat {
    case original
    case plainText
}

enum ViewerTab: Hashable {
    case history
    case snippets
}

enum ViewerAction: Equatable {
    enum Direction {
        case up, down
    }

    enum TabDirection: Equatable {
        case forward, backward
    }

    case move(Direction)
    case jumpToStart
    case jumpToEnd
    case switchTab(TabDirection)
    case paste(PasteFormat)
    case deleteSelected
    case clearHistory
    case close
}

enum ViewerActionDispatchPolicy {
    static let maximumMoveRepeatAge: TimeInterval = 0.1

    /// - Parameter age: Elapsed time since the event was posted, computed by the
    ///   caller as a single value from one monotonic clock (system uptime). Taking
    ///   a precomputed age rather than two raw timestamps keeps the policy from
    ///   ever mixing incompatible time bases.
    static func shouldDispatch(
        action: ViewerAction,
        isRepeat: Bool,
        age: TimeInterval
    ) -> Bool {
        guard isRepeat, case .move = action else { return true }
        return age <= maximumMoveRepeatAge
    }
}

@Observable
@MainActor
final class ViewerState {
    /// View-coordinating actions that require view/environment side effects.
    /// Movement actions are handled synchronously via perform().
    var pendingAction: ViewerAction?

    var selectedTab: ViewerTab = .history
    var selectedID: PersistentIdentifier?
    var itemIDs: [PersistentIdentifier] = []

    func perform(_ action: ViewerAction) {
        if case .switchTab(let direction) = action {
            switchTab(direction)
            return
        }
        if action == .close {
            pendingAction = action
            return
        }
        guard selectedTab == .history else { return }

        switch action {
        case .move(let direction):
            moveSelection(direction)
        case .jumpToStart:
            selectedID = itemIDs.first
        case .jumpToEnd:
            selectedID = itemIDs.last
        case .paste, .deleteSelected, .clearHistory:
            pendingAction = action
        case .switchTab, .close:
            break
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

    private func switchTab(_ direction: ViewerAction.TabDirection) {
        switch (selectedTab, direction) {
        case (.history, .forward):
            selectedTab = .snippets
        case (.snippets, .backward):
            selectedTab = .history
        case (.history, .backward), (.snippets, .forward):
            break
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
