import Foundation

enum ViewerAction: Equatable {
    enum Direction {
        case up, down
    }

    case move(Direction)
    case jumpToStart
    case jumpToEnd
    case paste
    case close
}

@Observable
@MainActor
final class ViewerState {
    var pendingAction: ViewerAction?
}
