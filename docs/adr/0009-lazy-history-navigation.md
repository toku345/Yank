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
- `ViewerPanelController` no longer performs a second full SwiftData fetch merely
  to seed navigation IDs. The mounted query owns synchronization with
  `ViewerState`.

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
- Mouse activation and accessibility remain explicit and testable.

Negative:

- Native `List` selection visuals and accessibility semantics must be recreated
  deliberately.
- A user holding a movement key during a stall may see fewer moves than the
  number of generated repeat events.

Risks:

- Manual row semantics can regress VoiceOver operation. Verification must cover
  labels, selected state, and activation in addition to visual behavior.
- The 100 ms threshold is intentionally UX policy rather than a platform
  constant. Tests fix its boundary behavior so future changes are explicit.

## Validation

A Time Profiler run mounted 1,000 synthetic rows and delivered 100 fresh `C-n`
events through `ViewerPanel.sendEvent`. Selection advanced from index zero to
index 100 in 175.61 ms, compared with the 943 ms baseline, an 81 percent
reduction. The trace contained no `NSTableView` samples and no potential hang.
Separate tests cover non-repeat input, the exact 100 ms boundary, stale repeats,
and a 1,000-row navigation state.

Coverage boundary. Automated tests exercise the pure `ViewerActionDispatchPolicy`
decision only. Two pieces are verified manually rather than by unit tests, since
neither is practical to drive without a live SwiftUI/AppKit host:

- the `ViewerPanel.sendEvent` wiring that derives `age` from
  `ProcessInfo.processInfo.systemUptime - event.timestamp` and passes
  `event.isARepeat` — confirmed via the Time Profiler run above;
- the 16 ms cancellable `SelectionScroller` `.task(id:)` that coalesces rapid
  movement into a single scroll to the latest selection — confirmed by observing
  a single terminal scroll during rapid navigation in the same run.

A regression in either would pass the policy unit tests, so changes there require
re-running the manual navigation/profiling check.
