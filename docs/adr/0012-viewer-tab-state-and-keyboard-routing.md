# ADR 0012: Viewer Tab State and Keyboard Routing

## Status

Accepted

## Context

Phase 2 adds History and Snippets modes to Yank's keyboard-driven viewer.
Issue #33 provides only the tab foundation; displaying, navigating, and pasting
saved snippets remains in Issue #59.

The viewer accepts input through both SwiftUI controls and
`ViewerPanel.sendEvent`. Command-Shift-Left Bracket and
Command-Shift-Right Bracket are familiar previous-tab and next-tab shortcuts in
macOS applications. Yank needs explicit window-level routing for them because a
SwiftUI control inside the panel may otherwise consume the key event.
This replaces the tentative Control-F and Control-B tab-switching extension
noted in ADR 0004.

History actions must also remain scoped to the visible History tab. Otherwise,
keys pressed while the Snippets placeholder is visible could move, paste, or
delete an item from the hidden history.

## Decision

Use a standard SwiftUI `TabView` with History and Snippets tabs. Store its
selection in `ViewerState.selectedTab` so mouse selection and keyboard actions
share one source of truth.

Map Command-Shift-Left Bracket and Command-Shift-Right Bracket in the viewer key
handler to backward and forward tab actions. `ViewerPanel.sendEvent` continues
to supply modifier state tracked through `flagsChanged`, and
`ViewerState.perform()` applies the tab transition directly. Tab movement stops
at the first or last tab rather than wrapping.

Match the bracket shortcuts by the character the key event produces
(`charactersIgnoringModifiers`), not by physical key code. `kVK_ANSI_*` codes
name ANSI physical positions, so key-code matching would break or invert the
shortcut on non-ANSI layouts such as JIS. While the Command-Shift chord is
held, the handler maps no other keys: Return, Escape, and Delete deliberately
do not paste, close, or delete until the modifiers are released.

While Snippets is selected, `ViewerState` ignores History-only movement, jump,
paste, delete, and clear actions. Close and tab-switch actions remain available.
The History tab owns its list, empty state, and deletion controls; the Snippets
tab contains only a placeholder until Issue #59.

Keep the selected tab for the lifetime of the running application, including
when the panel is closed and reopened. Do not persist it across application
launches. Continue loading history before presenting the panel and preserve the
existing fail-closed behavior if that load fails.

## Consequences

Positive:

- Mouse and keyboard tab selection cannot drift because both update the same
  state.
- Hidden history is not affected by input made while Snippets is visible.
- Tab switching does not consume Control-F or Control-B, leaving those standard
  cursor-movement bindings available to a future snippet editor.
- Issue #59 can add Snippets-specific selection and paste behavior without
  changing the window-level key routing.
- The UI uses the platform tab container without adding a dependency.

Negative:

- The automatic macOS tab appearance may change between operating-system
  versions.
- History identifiers are still loaded even when Snippets was the last selected
  tab.
- The Snippets tab is intentionally a placeholder until later Phase 2 work.
