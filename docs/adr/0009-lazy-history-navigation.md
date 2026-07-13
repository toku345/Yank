# ADR 0009: Lazy History Navigation and Stale Repeat Handling

## Status

Accepted

## Context

Profiling a synthetic 1,000-item viewer while processing one initial `C-n`
event and 99 repeat events took 0.943 seconds. `ViewerState` movement accounted
for about 5 ms, while SwiftUI AttributeGraph, Core Animation, and the
`NSTableView` backing `List(selection:)` dominated the trace. Selection changes
also triggered `ScrollViewReader.scrollTo` and reevaluation of the full query ID
array.

There is no code path that maps one `C-n` event directly to the final item.
When the main actor stalls, queued auto-repeat events are delivered in a burst
after it resumes, which makes a single perceived action appear to jump far down
the history.

ADR 0004 requires every movement event to synchronously update selection. That
fixed event loss caused by using observable state as an event channel, but it
did not distinguish current input from auto-repeat events delayed by a main
thread stall.

A follow-up unit test hosted synthetic history rows in an ordered `NSWindow`
and traversed the SwiftUI accessibility hierarchy. It passed in signed local
GUI test hosts with Xcode 16.4 and 26.4, but two runs on GitHub's `macos-15`
runner with Xcode 16.4 did not expose the expected row button within two
seconds. Treating a missing row as a reason to skip would also hide a real
accessibility regression, so runtime hierarchy traversal is not a reliable
default CI test for this view.

A later review found two remaining consistency gaps. `show()` could seed
selection from `ViewerState.itemIDs` before the mounted query had synchronized,
making an empty or stale selection interactive. A row button could also retain
keyboard focus while `C-n`, `C-p`, or an arrow key moved the selected ID; bare
Space would then activate the focused row instead of the selected row.

## Decision

Replace `List(selection:)` with `ScrollViewReader`, `ScrollView`, and
`LazyVStack`:

- `ViewerState.selectedID` remains the single source of truth.
- Rows render their selected state explicitly and expose an accessible button
  action that preserves click-to-paste behavior.
- Selection changes immediately, while scrolling is delayed for 16 ms in a
  cancellable task keyed by the selected ID. Rapid movement therefore scrolls
  only to the latest selection.
- Query ownership, list rendering, and history controls are separate observation
  boundaries so a selection-only change does not rebuild the full query ID
  array.
- Immediately before presentation, `ViewerPanelController` loads an
  identifier-only snapshot with the same newest-first sort as the mounted query.
  It uses a fresh `ModelContext`, excludes pending changes, synchronizes
  `ViewerState.itemIDs`, and selects the first ID before the panel is interactive.
  The mounted query continues to own ongoing synchronization.
- If the identifier snapshot fails, clear stale navigation state, report the
  error, and do not present the panel.

The identifier snapshot uses `fetchIdentifiers` so presentation does not
materialize a second array of `ClipItem` objects. This was chosen over a
query-readiness handshake, which would add presentation and input-gating state.

Centralize each row's label, selected state, and activation in an internal
`HistoryRowContract` used directly by `HistoryRowButton`. The contract:

- derives the accessibility label from `ClipItem.title`;
- compares the row identifier with `ViewerState.selectedID`;
- updates the selection before invoking the item callback.

History row buttons do not participate in keyboard focus. Keyboard users move
selection with `C-n`, `C-p`, or the arrow keys and paste the selected item with
Return or Control-Return. Pointer and accessibility activation continue to
invoke the row contract. This avoids maintaining separate selected and focused
rows. A `FocusState` synchronization layer was rejected because lazy off-screen
rows may not exist when selection changes, and a row-local Space handler was
rejected because its ordering relative to the button's built-in activation is
not part of the API contract.

Automated tests will exercise this same contract without traversing the runtime
accessibility hierarchy. The SwiftUI-to-AppKit accessibility bridge and
VoiceOver behavior remain manual validation boundaries.

Amend ADR 0004's event contract as follows:

- a non-repeat movement event always produces exactly one movement;
- an auto-repeat movement event no more than 100 ms old produces exactly one
  movement;
- an auto-repeat movement event older than 100 ms is stale and may be discarded;
- paste, delete, close, and jump actions are never discarded by this policy.

Event age is calculated from `NSEvent.timestamp` and system uptime. The caller
computes this as a single `age` value from one monotonic clock and passes it to
`ViewerActionDispatchPolicy.shouldDispatch(action:isRepeat:age:)`; the policy
never receives two raw timestamps, so it cannot mix incompatible time bases. The
policy is a safety net for already-delayed input, not a substitute for reducing
view update cost.

## Consequences

Positive:

- History navigation no longer crosses SwiftUI's two-way List/NSTableView
  selection bridge.
- Only visible rows are constructed, and scroll work is coalesced during rapid
  input.
- Input queued during a long main-thread stall cannot replay all the way to the
  end of the list.
- Mouse activation and row semantics share one explicit, deterministic contract.
- The panel does not become interactive using navigation IDs carried over from
  a previous presentation.
- A previously focused row cannot override the selected row through bare Space.

Negative:

- Native `List` selection visuals and accessibility semantics must be recreated
  deliberately.
- A user holding a movement key during a stall may see fewer moves than the
  number of generated repeat events.
- Each presentation performs one synchronous identifier-only fetch.
- Full Keyboard Access cannot move keyboard focus onto a history row; the
  viewer's navigation and Return bindings are the keyboard interaction path.

Risks:

- Removing or misattaching a SwiftUI accessibility modifier can pass the
  contract tests. Release verification must therefore cover the emitted role,
  label, selected state, focus traversal, and activation.
- Disabling keyboard focus must not remove history rows from VoiceOver traversal
  or prevent VoiceOver activation.
- Identifier snapshot latency must be checked with a large history so the
  correctness boundary does not create a panel-open stall.
- The 100 ms threshold is intentionally UX policy rather than a platform
  constant. Tests fix its boundary behavior so future changes are explicit.

## Validation

A Time Profiler run mounted 1,000 synthetic rows and delivered 100 fresh `C-n`
events through `ViewerPanel.sendEvent`. Selection advanced from index zero to
index 100 in 175.61 ms, compared with the 943 ms baseline, an 81 percent
reduction. The trace contained no `NSTableView` samples and no potential hang.
Tests cover non-repeat input, the exact 100 ms boundary, stale repeats, and a
1,000-row navigation state. `ViewerPanelTests` also injects a deterministic
uptime provider and sends key events through `ViewerPanel.sendEvent`, proving
that a fresh repeat is dispatched, a stale repeat is discarded, and a stale
non-repeat is still dispatched. This covers the timestamp subtraction and
`event.isARepeat` wiring rather than only the pure policy.

Presentation tests must cover newest-first identifier ordering, replacement of
stale IDs, empty history, and snapshot failure without showing the panel. A
1,000-item presentation profile must confirm that the identifier snapshot does
not materially regress panel-open latency.

An Xcode 16.4 `XCTClockMetric` run on macOS 26.5.1 measured `show()` against a
temporary on-disk SwiftData store containing 1,000 synthetic text clips. The
presenter was replaced with a no-op to isolate the identifier snapshot, state
synchronization, and panel preparation from WindowServer effects. The first
presentation took 0.484 ms; four subsequent presentations took 0.255-0.322 ms,
for a five-run mean of 0.325 ms. This is below one millisecond and does not
materially regress panel-open latency.

A signed local ordered-`NSWindow` fixture on macOS 26.5.1 verified the runtime
bridge with Xcode 16.4 and 26.4: rows exposed the `AXButton` role and clip title,
reflected selection, and routed accessibility activation to the item callback.
This historical fixture predates keyboard-focus suppression and did not exercise
VoiceOver or the real nonactivating `ViewerPanel`.

The 16 ms cancellable `SelectionScroller` was also confirmed manually during
the profiling run above to issue one terminal scroll during rapid navigation.

Before release, and whenever row accessibility semantics change, use VoiceOver
to verify that focus traverses the rows; the clip title, button role, and
selected state are announced; `C-n` / `C-p` updates the announced selection;
and VO-Space activation on another row pastes the expected original-format
item. With Full Keyboard Access enabled, verify that rows do not retain keyboard
focus, bare Space does not paste a stale row, Return pastes the selected row,
and the history-control buttons still accept Space.

Keyboard-focus suppression is not complete and must not be merged until an app
built with Xcode 16.4 passes this checklist on a macOS 14 runtime. If disabling
keyboard focus prevents VoiceOver traversal or activation, do not adopt
`.focusable(false)`; revisit the focus design instead.
