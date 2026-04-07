# ADR 0001: Phase 1 Redesign — Coordinator + Action Enum Architecture

## Status

Accepted

## Context

PR #4 (`feature/phase1-core-implementation`) implemented Phase 1 MVP with +1,157 lines across 18 files and 16 commits. While the component responsibilities were sound (ClipboardMonitor, HotKeyManager, PasteEngine, ViewerPanel, EmacsKeyHandler), the implementation accumulated complexity from trial-and-error debugging:

- **Keyboard state management** used 5 independent boolean flags (`shouldPaste`, `shouldClose`, `moveDirection`, `shouldJumpToStart`, `shouldJumpToEnd`) with no guarantee of mutual consistency, requiring 5 separate `onChange` blocks in `ViewerContentView`.
- **Component wiring** was embedded directly in `AppDelegate`, mixing macOS lifecycle with initialization logic.
- **Type detection** used fragile string matching (`primaryType.contains("rtf")`) that could break across macOS versions.
- **`ObservableObject`** was used for `KeyboardState` despite targeting macOS 14+ where `@Observable` is available.
- **ClipItem** carried Phase 2/3 properties (`isSensitive`, `isPinned` partially) violating YAGNI.

The goal of the redesign is a simpler, more maintainable Phase 1 with the same feature set.

## Decision

Adopt **Approach A: Coordinator + Action Enum** with the following changes:

### Architecture

1. **AppCoordinator** — A dedicated `@MainActor` class owns component lifecycle and wiring. `AppDelegate` becomes a thin shell that delegates to the coordinator.

2. **ViewerAction enum** — Replaces 5 boolean flags with a single discriminated union:
   ```swift
   enum ViewerAction: Equatable {
       case move(Direction), jumpToStart, jumpToEnd, paste, close
   }
   ```
   Bridged via `@Observable ViewerState` (1 property: `pendingAction: ViewerAction?`).

3. **UTType API** — Replaces string-based type detection with `UTType.conforms(to:)` for clipboard type identification and display badges.

4. **@Observable** — Used for `ViewerState` instead of `ObservableObject`, leveraging macOS 14+ availability.

5. **Startup Accessibility check** — `AXIsProcessTrustedWithOptions` called at launch to surface permission issues immediately instead of silent CGEvent failures.

### Data model (ClipItem)

- Removed: `isSensitive` (Phase 3), `isPinned` (Phase 3), `urlStrings` (captured in `stringValue`)
- Added: `htmlData` (common web copy type), `pngData` merged into `imageData` (TIFF-normalized)
- Added: `primaryUTType` computed property for type-safe comparison
- Snippet/SnippetFolder deferred to Phase 2 (not created in Phase 1)

### What stays the same

- **Component responsibilities**: ClipboardMonitor, HotKeyManager, PasteService, ViewerPanel, EmacsKeyHandler
- **Carbon API** for global hotkeys (no modern Apple alternative exists)
- **NSPanel** for floating viewer window
- **Timer + changeCount polling** for clipboard monitoring
- **CGEvent** for Cmd+V simulation

### Reference projects

- [Clipy](https://github.com/Clipy/Clipy) (MIT License) — Clipboard monitoring, paste execution, hotkey registration, data model design
- [Maccy](https://github.com/p0deje/Maccy) (MIT License, Copyright 2025 Alex Rodionov) — Self-paste suppression pattern (custom pasteboard type), CGEvent configuration parameters

## Consequences

**Positive:**
- Keyboard event handling consolidated from 5 `onChange` blocks to 1 `switch` statement
- PasteService and ClipboardMonitor are fully decoupled (no shared lock)
- Type detection is robust across macOS versions via UTType API
- Accessibility issues are surfaced at launch, not discovered through silent paste failures

**Negative:**
- Full reimplementation of Phase 1 (not incremental improvement of PR #4)
- Carbon API's `Unmanaged` pattern remains unavoidable

**Risks:**
- Paste flow without delays may not work on all machines — mitigated by staged verification approach (see ADR 0003)
