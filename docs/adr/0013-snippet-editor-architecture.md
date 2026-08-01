# ADR 0013: Snippet Editor Architecture

## Status

Accepted

## Context

Issue #34 adds the first user-facing writer for the snippet models introduced in ADR 0010. The editor must share Yank's existing SwiftData store, preserve dense folder and snippet ordering, support drag-and-drop moves, and avoid losing explicit-save drafts when selection or window state changes.

The application currently creates its `ModelContainer` in `AppCoordinator` and uses AppKit-owned windows hosting SwiftUI content. Moving container ownership to a SwiftUI `Window` scene would broaden this slice and risk opening the same store through independently-created containers.

## Decision

`AppCoordinator` owns a reusable AppKit `NSWindow` controller for the snippet editor. The controller hosts a three-column SwiftUI `NavigationSplitView` and injects the application's existing `ModelContainer`.

Editor selection and unsaved fields live in a dedicated observable state object as persistent identifiers and plain-value drafts. SwiftData models are only mutated when an explicit operation is saved. Selection changes, moves, window closing, and application termination pass through one dirty-draft decision boundary supporting Save, Discard, and Cancel.

Mutation helpers are stateless and receive the shared main `ModelContext` for each operation. They require a clean context before starting, normalize folder and per-folder snippet order to dense zero-based integers, save once, and roll back on failure. Clipboard persistence continues to use its existing separate context.

Drag-and-drop uses an app-specific transferable payload containing an opaque UUID token. A registry owned by the reusable editor window maps each token to an item kind and SwiftData `PersistentIdentifier` for that window's lifetime. Drop handlers reject unknown tokens, then resolve and validate the identifier in the current context before applying any change. A Move to Folder menu remains available so drag-and-drop is not the only movement path.

## Consequences

Positive:

- The editor and viewer observe one container without changing schema ownership.
- Unsaved text never becomes an incidental SwiftData pending change.
- Reordering and cross-folder moves share one tested ordering invariant.
- Window closing and selection changes cannot silently discard a draft.

Negative:

- The editor adds an AppKit controller around otherwise SwiftUI content.
- Shared-context mutations must fail closed if unrelated pending changes exist.
- Custom drag payload validation adds more code than list-local reordering alone.
