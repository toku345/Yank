# ADR 0008: Off-Main Clipboard Persistence

## Status

Accepted

## Context

Time Profiler showed a 291.98 ms main-thread microhang while retaining a
synthetic 128 MB TIFF clipboard item. The dominant sampled work was the
synchronous SwiftData insert/save and history prune performed by
`ClipboardMonitor`, which is isolated to `MainActor`.

Yank must continue to retain full-fidelity clipboard payloads. Applying an
image size cap, generating thumbnails, or dropping rich representations would
change the product behavior and is outside this performance fix.

The existing prune implementation deletes at most 100 rows at a time and uses
delayed continuation tasks so that main-thread work can yield between batches.
Once persistence moves off the main actor, that continuation machinery no
longer serves its original purpose.

## Decision

Keep pasteboard polling and reads on `MainActor`, then hand an immutable,
`Sendable` snapshot to a plain `ClipboardHistoryWriter` actor.

The writer:

- owns and reuses one `ModelContext` created from the application's
  `ModelContainer`;
- normalizes captured values, derives the title, and computes the content
  fingerprint on its own executor;
- updates its last-persisted fingerprint only after the insert has been saved;
- retries an insert save once after rollback and reconstruction of the model;
- fetches and deletes all rows beyond the history limit in one off-main prune;
- retries the prune save once, while retaining an already-saved new item if
  pruning ultimately fails.

`ClipboardMonitor` permits one persistence operation at a time. It checks that
gate before advancing `lastChangeCount`. When the operation completes, the
monitor polls again so a change that arrived while the writer was busy is
captured. Intermediate changes may still collapse to the latest pasteboard
state, matching the existing 250 ms polling behavior.

Clear All pauses polling, advances the capture barrier to the confirmed
pasteboard state, drains any in-flight capture, and then asks the same writer
actor to refetch and delete every stored item. Normal app termination uses
AppKit's deferred-termination reply to drain active persistence before exit.

The capture timestamp is recorded on `MainActor` and carried in the snapshot.
It is not generated later by the writer because actor scheduling delay must not
change history ordering.

Do not use `@ModelActor`, a worker protocol/factory hierarchy, or one detached
task and `ModelContext` per snapshot. The plain actor provides serialization,
context confinement, reuse, and a direct test surface with less infrastructure.

## Consequences

Positive:

- SwiftData save and prune no longer block keyboard or SwiftUI work on the main
  actor.
- Full-fidelity clipboard representations and the existing schema are retained.
- Batch size, continuation delay, and continuation task state are removed.
- Fingerprint and timestamp behavior remains deterministic across failures and
  actor scheduling delays.

Negative:

- Pasteboard reads remain synchronous AppKit work on the main actor.
- Only one captured snapshot can be in flight; multiple changes during a save
  collapse to the newest pasteboard state.
- A permanently failing prune can temporarily leave more than the configured
  history limit until a later capture retries pruning.
- Clear All and normal termination can wait for a large synchronous store
  operation already running on the writer actor.

Risks:

- SwiftData background-context saves must refresh an already-mounted `@Query`.
  This is covered by an in-memory integration test and manual runtime
  verification. If it does not hold on the deployment target, the change must
  stop for a data-layer redesign rather than add an implicit merge protocol.
- Cancellation cannot interrupt a synchronous SwiftData save already in
  progress. Stopping the monitor suppresses completion-time polling, and normal
  termination is deferred until the active store operation finishes.

## Validation

A Time Profiler run used a temporary SwiftData store containing 1,000 synthetic
rows and then persisted a synthetic 128 MiB TIFF payload. The writer completed
in 561.38 ms while the main-run-loop probe's largest gap was 6.27 ms. Instruments
reported no potential hang, and all sampled `ClipboardHistoryWriter` insert,
save, fingerprint, and prune work ran on the writer actor rather than the main
thread.

The test suite also mounts an `@Query` against an in-memory container and
verifies that writer-context insert and prune saves update the observed values
without a manual merge channel. Deterministic gates cover Clear All and
termination while a capture is in flight.
