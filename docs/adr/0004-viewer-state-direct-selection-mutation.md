# ADR 0004: ViewerState Direct Selection Mutation

## Status

Accepted

## Context

ADR 0001 introduced `ViewerState` with a single `pendingAction: ViewerAction?` property as a bridge between AppKit (`ViewerPanel.keyDown`) and SwiftUI (`ViewerContentView.onChange`). This consolidated 5 boolean flags into 1 discriminated union and was a significant improvement.

However, `pendingAction` uses `@Observable` — a **state** observation mechanism — to convey **events** (discrete occurrences). This works for single key presses but fails during key repeat:

1. `keyDown(C-n)` sets `pendingAction = .move(.down)`.
2. SwiftUI schedules `onChange` for the next runloop cycle.
3. Before `onChange` fires, the next key repeat sets `pendingAction = .move(.down)` again.
4. `@Observable` sees no value change — `onChange` does not re-fire.
5. The second event is silently swallowed.

This causes C-n/C-p to stutter during key repeat (Issue #6). Observed symptoms include:
- Key repeat producing fewer moves than expected (events silently swallowed)
- Rare oscillation where C-p causes the cursor to bounce between two adjacent items — likely a conflict between the programmatic `selectedID` update and the List's internal selection state propagating back through the two-way binding before the next `onChange` cycle

Arrow keys are likely handled natively by the List's internal NSTableView before reaching `ViewerPanel.keyDown`, though this needs verification during implementation. If so, the arrow key cases in `EmacsKeyHandler.handlePlain` may be dead code.

## Decision

Split `ViewerState` responsibilities by action type:

- **Movement actions** (`move`, `jumpToStart`, `jumpToEnd`): Mutate `selectedID` directly and synchronously within `ViewerState.perform()`. No intermediate event passing.
- **View-coordinating actions** (`paste`, `close`): Continue using `pendingAction` — these are one-shot actions that don't suffer from key repeat, and they require View-level context (e.g., looking up `ClipItem` by ID for paste).

`ViewerState` gains:
- `selectedID: PersistentIdentifier?` — selection state, previously `@State` in `ViewerContentView`
- `itemIDs: [PersistentIdentifier]` — ordered list of item IDs, synced from `ViewerContentView.onChange(of: clipItems)`
- `perform(_ action: ViewerAction)` — single entry point called from `ViewerPanel.keyDown`

`EmacsKeyHandler` remains unchanged as a pure function.

`ViewerContentView` passes a two-way `Binding` to `List(selection:)` via `Bindable(viewerState).selectedID`. The List's native selection handling (mouse clicks, arrow keys if they reach the List) also updates `selectedID` through this binding — selection state converges regardless of the input source.

## Consequences

**Positive:**
- Each `keyDown` event maps to exactly one selection change — no events lost during key repeat
- Selection logic is testable without SwiftUI view instantiation
- `perform()` provides a natural extension point for Phase 2 keybindings (C-f/C-b tab switching)
- `pendingAction` scope narrows to actions that genuinely need async View coordination

**Negative:**
- `ViewerState` now holds `itemIDs`, which must be kept in sync with the `@Query` result in `ViewerContentView`
- Slightly more state in `ViewerState` (was 1 property, now 3 properties + 1 method)

**Risks:**
- If `itemIDs` sync drifts from the actual `@Query` result (e.g., a SwiftData insert occurs between syncs), selection could briefly reference a stale index. Mitigation: `moveSelection` guards against out-of-bounds via `min`/`max` clamping, and the next `onChange(of: clipItems)` resynchronizes immediately.
- If arrow keys are handled natively by the List (hypothesis A in Context) and the `handlePlain` arrow key cases in `EmacsKeyHandler` remain, the same move action could fire twice (List native + `ViewerState.perform`). Verify during implementation and remove redundant cases if confirmed.
