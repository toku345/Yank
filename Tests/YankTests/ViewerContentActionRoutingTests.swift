import XCTest
@testable import Yank

final class ViewerContentActionRoutingTests: XCTestCase {
    private struct ActionAvailabilityCase {
        let action: ViewerAction
        let availableInHistory: Bool
        let availableInSnippets: Bool
    }

    func testCloseInSnippetsInvokesCloseOnly() {
        var closeCount = 0
        var historyActions: [ViewerAction] = []

        ViewerContentActionRouting.handle(
            action: .close,
            selectedTab: .snippets,
            onClose: { closeCount += 1 },
            onHistoryAction: { historyActions.append($0) },
            onSnippetPaste: { XCTFail("Unexpected snippet paste") }
        )

        XCTAssertEqual(closeCount, 1)
        XCTAssertTrue(historyActions.isEmpty)
    }

    func testHistoryOnlySideEffectsInSnippetsAreIgnored() {
        var closeCount = 0
        var historyActions: [ViewerAction] = []

        for action in historyOnlySideEffects {
            ViewerContentActionRouting.handle(
                action: action,
                selectedTab: .snippets,
                onClose: { closeCount += 1 },
                onHistoryAction: { historyActions.append($0) },
                onSnippetPaste: { XCTFail("Unexpected snippet paste") }
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
                onHistoryAction: { historyActions.append($0) },
                onSnippetPaste: { XCTFail("Unexpected snippet paste") }
            )
        }

        XCTAssertEqual(historyActions, historySideEffects)
    }

    func testPasteFormatsInSnippetsInvokeSnippetCallbackOnly() {
        var snippetPasteCount = 0
        var historyActions: [ViewerAction] = []

        for action in [ViewerAction.paste(.original), .paste(.plainText)] {
            ViewerContentActionRouting.handle(
                action: action,
                selectedTab: .snippets,
                onClose: {},
                onHistoryAction: { historyActions.append($0) },
                onSnippetPaste: { snippetPasteCount += 1 }
            )
        }

        XCTAssertEqual(snippetPasteCount, 2)
        XCTAssertTrue(historyActions.isEmpty)
    }

    func testActionAvailabilityMatchesDeclaredScopeForBothTabs() {
        for testCase in actionAvailabilityCases {
            XCTAssertEqual(
                testCase.action.isAvailable(in: .history),
                testCase.availableInHistory,
                "Unexpected History availability for \(testCase.action)"
            )
            XCTAssertEqual(
                testCase.action.isAvailable(in: .snippets),
                testCase.availableInSnippets,
                "Unexpected Snippets availability for \(testCase.action)"
            )
        }
    }

    private var historySideEffects: [ViewerAction] {
        [.paste(.original), .paste(.plainText), .deleteSelected, .clearHistory]
    }

    private var historyOnlySideEffects: [ViewerAction] {
        [.deleteSelected, .clearHistory]
    }

    private var actionAvailabilityCases: [ActionAvailabilityCase] {
        [
            ActionAvailabilityCase(action: .move(.down), availableInHistory: true, availableInSnippets: true),
            ActionAvailabilityCase(action: .jumpToStart, availableInHistory: true, availableInSnippets: true),
            ActionAvailabilityCase(action: .jumpToEnd, availableInHistory: true, availableInSnippets: true),
            ActionAvailabilityCase(action: .switchTab(.forward), availableInHistory: true, availableInSnippets: true),
            ActionAvailabilityCase(action: .paste(.original), availableInHistory: true, availableInSnippets: true),
            ActionAvailabilityCase(action: .paste(.plainText), availableInHistory: true, availableInSnippets: true),
            ActionAvailabilityCase(action: .deleteSelected, availableInHistory: true, availableInSnippets: false),
            ActionAvailabilityCase(action: .clearHistory, availableInHistory: true, availableInSnippets: false),
            ActionAvailabilityCase(action: .close, availableInHistory: true, availableInSnippets: true)
        ]
    }
}
