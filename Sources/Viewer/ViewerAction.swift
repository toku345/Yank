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
    var selectedHistoryID: PersistentIdentifier?
    var historyItemIDs: [PersistentIdentifier] = []
    var selectedSnippetID: PersistentIdentifier?
    var snippetIDs: [PersistentIdentifier] = []

    func perform(_ action: ViewerAction) {
        switch action {
        case .switchTab(let direction):
            switchTab(direction)
        case .close:
            pendingAction = action
        case .move(let direction):
            moveActiveSelection(direction)
        case .jumpToStart:
            jumpActiveSelection(to: .start)
        case .jumpToEnd:
            jumpActiveSelection(to: .end)
        case .paste, .deleteSelected, .clearHistory:
            guard selectedTab == .history else { return }
            pendingAction = action
        }
    }

    func replaceHistoryItems(with newIDs: [PersistentIdentifier]) {
        historyItemIDs = newIDs
        selectedHistoryID = reconciledSelection(
            selectedHistoryID,
            in: newIDs
        )
    }

    func removeHistoryItem(id: PersistentIdentifier) {
        guard let removedIndex = historyItemIDs.firstIndex(of: id) else {
            replaceHistoryItems(with: historyItemIDs)
            return
        }

        let newIDs = historyItemIDs.filter { $0 != id }
        historyItemIDs = newIDs
        guard !newIDs.isEmpty else {
            selectedHistoryID = nil
            return
        }
        selectedHistoryID = newIDs[min(removedIndex, newIDs.count - 1)]
    }

    func clearHistoryItems() {
        historyItemIDs = []
        selectedHistoryID = nil
    }

    func replaceSnippets(with newIDs: [PersistentIdentifier]) {
        snippetIDs = newIDs
        selectedSnippetID = reconciledSelection(
            selectedSnippetID,
            in: newIDs
        )
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

    private enum JumpTarget {
        case start, end
    }

    private func moveActiveSelection(_ direction: ViewerAction.Direction) {
        switch selectedTab {
        case .history:
            selectedHistoryID = movedSelection(
                selectedHistoryID,
                in: historyItemIDs,
                direction: direction
            )
        case .snippets:
            selectedSnippetID = movedSelection(
                selectedSnippetID,
                in: snippetIDs,
                direction: direction
            )
        }
    }

    private func jumpActiveSelection(to target: JumpTarget) {
        switch (selectedTab, target) {
        case (.history, .start):
            selectedHistoryID = historyItemIDs.first
        case (.history, .end):
            selectedHistoryID = historyItemIDs.last
        case (.snippets, .start):
            selectedSnippetID = snippetIDs.first
        case (.snippets, .end):
            selectedSnippetID = snippetIDs.last
        }
    }

    private func reconciledSelection(
        _ selectedID: PersistentIdentifier?,
        in newIDs: [PersistentIdentifier]
    ) -> PersistentIdentifier? {
        guard !newIDs.isEmpty else { return nil }
        guard let selectedID, newIDs.contains(selectedID) else {
            return newIDs.first
        }
        return selectedID
    }

    private func movedSelection(
        _ selectedID: PersistentIdentifier?,
        in itemIDs: [PersistentIdentifier],
        direction: ViewerAction.Direction
    ) -> PersistentIdentifier? {
        guard !itemIDs.isEmpty else { return nil }
        let currentIndex = selectedID.flatMap { id in
            itemIDs.firstIndex(of: id)
        } ?? -1
        switch direction {
        case .down:
            return itemIDs[min(currentIndex + 1, itemIDs.count - 1)]
        case .up:
            return itemIDs[max(currentIndex - 1, 0)]
        }
    }
}
