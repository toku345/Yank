# ADR 0015: Display and Paste Snippets from the Viewer

## Status

Accepted

## Context

ADR 0012 introduced History and Snippets tabs while leaving the Snippets tab as
a placeholder. Issue #59 completes that viewer flow. Saved folders and snippets
must remain visibly structured in their persisted order, keyboard navigation
must follow the active tab, and snippet paste must preserve Yank's existing
self-paste suppression and synthetic Cmd+V behavior.

The History path already keeps pasteboard and application side effects outside
SwiftUI by passing callbacks through `ViewerPanelController` to
`AppCoordinator`. Snippet paste should follow the same boundary without
refactoring History requests into a new abstraction.

## Decision

Render saved folders as non-selectable structural rows and snippets as
keyboard-selectable title rows. `ViewerState.selectedSnippetID` remains the
selection source of truth, and the list scrolls to programmatic selection in
the same way as History.

Classify every `ViewerAction` as global, active-tab, or History-only. Both
`ViewerState` and view-side action routing consult the same availability API.
Movement, jump, and paste act on the active tab; close and tab switching remain
global; delete and clear remain History-only.

Use a dedicated snippet-paste callback from `ViewerContentView` through
`ViewerPanelController` to `AppCoordinator`. Snippets always write their content
as plain text with Yank's self-paste suppression marker. Bare Return and
Control-Return therefore have the same result in the Snippets tab. After a
successful write, reuse the existing write, close, accessibility-check, and
Cmd+V sequence. A failed write leaves the panel open and restores the prior
clipboard contents.

Keep the existing SwiftData query synchronization and its one-frame coalescing
workaround. Replacing it with a shared collection store remains the separate
follow-up tracked by Issue #82.

## Consequences

Positive:

- Saved snippets are usable from the same keyboard-driven viewer as History.
- Folder structure is visible without making folders part of keyboard
  selection.
- One action-scope definition prevents state and view routing from silently
  disagreeing as actions are added.
- Snippet paste shares History's clipboard preservation, self-paste
  suppression, panel-close, and accessibility behavior.

Negative:

- The viewer retains separate History and Snippet paste callbacks.
- Snippet query synchronization remains timing-dependent until Issue #82.
- Empty snippet content is pasted as an empty plain-text value, replacing the
  current clipboard when the user explicitly activates it.
