import XCTest
@testable import Yank

final class ViewerContentActionRoutingTests: XCTestCase {
    func testCloseInSnippetsInvokesCloseOnly() {
        var closeCount = 0
        var historyActions: [ViewerAction] = []

        ViewerContentActionRouting.handle(
            action: .close,
            selectedTab: .snippets,
            onClose: { closeCount += 1 },
            onHistoryAction: { historyActions.append($0) }
        )

        XCTAssertEqual(closeCount, 1)
        XCTAssertTrue(historyActions.isEmpty)
    }

    func testHistorySideEffectsInSnippetsAreIgnored() {
        var closeCount = 0
        var historyActions: [ViewerAction] = []

        for action in historySideEffects {
            ViewerContentActionRouting.handle(
                action: action,
                selectedTab: .snippets,
                onClose: { closeCount += 1 },
                onHistoryAction: { historyActions.append($0) }
            )
        }

        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(historyActions.isEmpty)
    }

    func testHistorySideEffectsInHistoryAreForwarded() {
        var historyActions: [ViewerAction] = []

        for action in historySideEffects {
            ViewerContentActionRouting.handle(
                action: action,
                selectedTab: .history,
                onClose: {},
                onHistoryAction: { historyActions.append($0) }
            )
        }

        XCTAssertEqual(historyActions, historySideEffects)
    }

    private var historySideEffects: [ViewerAction] {
        [.paste(.original), .deleteSelected, .clearHistory]
    }
}
