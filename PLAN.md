# Yank Development Plan

## Purpose

Yank is a keyboard-first clipboard manager for macOS 15 or later. It is inspired
by Clipy and uses native macOS frameworks to provide fast clipboard history and
reusable snippets without external runtime dependencies.

This document records long-term product direction, phase outcomes, and completion
criteria. It does not track day-to-day progress or implementation order. GitHub
Issues and the active milestone are canonical for live work. `README.md` exposes
only a short public status summary, and `docs/adr/` records durable architecture
decisions.

## Product Principles

- Keep the primary workflow fast and keyboard-first.
- Preserve clipboard representations faithfully when capturing and restoring data.
- Prefer platform frameworks and zero external dependencies.
- Make persistence, retention, and security limitations explicit.
- Deliver complete, independently useful slices without regressing clipboard history.

## Technical Direction

- **UI:** SwiftUI, with AppKit where macOS window behavior requires it.
- **Persistence:** SwiftData.
- **Global hotkey:** Carbon `RegisterEventHotKey`.
- **Paste execution:** CGEvent-based Cmd+V simulation.
- **Clipboard monitoring:** `Timer` and `NSPasteboard.changeCount` at a 250 ms interval.
- **Project generation:** XcodeGen using `project.yml`.
- **Deployment target:** macOS 15 Sequoia or later (ADR 0011).
- **Dependency policy:** Use platform APIs by default. Introduce an external
  dependency only when platform APIs cannot reasonably satisfy a requirement,
  and record that decision in an ADR.

## Roadmap

### Phase 1 — Clipboard History MVP

**Outcome: complete.**

Yank runs as a menu bar application, captures clipboard history, opens a
keyboard-driven viewer with Cmd+Shift+V, restores selected clipboard content,
and provides bounded retention and manual deletion controls.

### Phase 2 — Snippet Management

**Outcome:** Users can organize reusable plain-text snippets and paste them from
the same keyboard-driven viewer used for clipboard history.

Phase 2 is complete when:

- snippet folders and snippets are persisted with stable user-defined ordering;
- users can create, edit, delete, and reorder folders and snippets;
- the viewer provides History and Snippets tabs, switchable with C-f and C-b;
- folders and snippets are displayed in saved order and support C-n, C-p, C-a,
  and C-e navigation;
- Return pastes the selected snippet as plain text through the existing paste
  flow, suppresses Yank's own clipboard write, and closes the viewer;
- empty snippet states are clear and do not affect clipboard-history behavior;
- users can start a Clipy XML import from the snippet editor;
- successful imports are persisted, while invalid imports fail atomically with
  user-visible feedback.

Search, configurable retention, and sensitive-item policies are outside Phase 2.

### Phase 3 — Privacy and Daily-Use Improvements

**Outcome:** Yank provides stronger privacy controls and integrates cleanly into
daily macOS use.

Candidate outcomes include:

- configurable history count and age-based expiration;
- sensitive-item classification and automatic deletion after paste;
- incremental search;
- launch-at-login support;
- expanded menu bar controls and usable settings.

The exact scope and order remain in GitHub Issues and future milestones.

## Distribution Direction

Local Production installation is supported. Public GitHub distribution remains
deferred until there is a concrete external-user need and is tracked separately
in [Issue #53](https://github.com/toku345/Yank/issues/53). A public artifact must
pass Developer ID signing, notarization, stapling, and Gatekeeper verification.

## Cross-Phase Completion Standards

- Relevant builds and tests pass on the supported macOS version.
- Existing clipboard-history and keyboard workflows do not regress.
- User-visible behavior and limitations are documented.
- Durable architecture decisions are recorded in `docs/adr/`.
- Security and privacy changes include an explicit threat-model assessment.

## Maintaining This Plan

Update this file only when product principles, phase outcomes, or completion
criteria change. Do not use it to mirror Issue status, assignments, dependencies,
or implementation order.
