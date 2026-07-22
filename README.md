# Yank

A clipboard manager for macOS, successor to [Clipy](https://github.com/Clipy/Clipy). Built with SwiftUI + SwiftData, no runtime dependencies.

## Project Status

- **Current app version in source:** `0.1.0` (no public version tag or GitHub Release has been published)
- **Active milestone:** [0.2.0 — Snippet management](https://github.com/toku345/Yank/milestone/1)
- **Current focus:** [#32 Add snippet data models](https://github.com/toku345/Yank/issues/32)
- **Public distribution:** Deferred; see [Issue #53](https://github.com/toku345/Yank/issues/53)

## Features

### Implemented (Phase 1 MVP)

- **Clipboard history** — automatically captures text, RTF, HTML, PDF, images, and file URLs
- **Global hotkey** — Cmd+Shift+V to open/close the history viewer
- **Emacs keybindings** — C-n/C-p (up/down), C-a/C-e (jump to start/end), C-g (close)
- **Paste simulation** — select an item and press Return to paste via CGEvent Cmd+V
- **Self-paste suppression** — Yank's own paste operations are excluded from history
- **Duplicate detection** — consecutive identical clipboard contents are deduplicated
- **History deletion controls** — delete the selected history item or clear all saved history
- **Menu bar app** — status item with About and Quit actions

### Planned

- **Snippet management** — folder-organized snippets with C-f/C-b tab switching (Phase 2)
- **Clipy snippet import** — import existing Clipy XML snippets (Phase 2)
- **Expanded menu bar controls and settings** — viewer access and usable preferences from the menu bar (Phase 3)
- **Sensitive value handling** — sensitive classification and auto-delete after paste (Phase 3)
- **Launch at login** — via SMAppService (Phase 3)
- **Search** — incremental search with C-s (Phase 3)

## Requirements

- macOS 15 Sequoia or later
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting Started

### Build & Run

```bash
# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project Yank.xcodeproj -scheme Yank -configuration Debug build

# Launch the app
open ~/Library/Developer/Xcode/DerivedData/Yank-*/Build/Products/Debug/Yank.app

# Or run directly from Xcode: Product > Run (Cmd+R)
```

On first launch, macOS will prompt for **Accessibility permission** (required for paste simulation via Cmd+V). Grant it in **System Settings > Privacy & Security > Accessibility**.

> **Note:** With the default ad-hoc signing, each debug build changes the code signature and macOS revokes the Accessibility grant. Set up a stable development signing identity (see [docs/dev-signing.md](docs/dev-signing.md)) to keep the permission across builds. If paste still stops working, remove Yank from the Accessibility list and re-add it.

### Local Production Install

To create an optimized, Universal (`arm64` + `x86_64`) Release archive signed
with your local Apple Development identity and install it in `/Applications`:

```bash
# One-time signing setup
open docs/dev-signing.md

# Build, verify, install, and launch /Applications/Yank.app
./scripts/install-production.sh
```

The installer fails closed if the app is ad-hoc signed, lacks hardened runtime,
contains the debugger entitlement, has unexpected metadata, or is missing an
architecture. It only replaces an existing app whose bundle identifier is
`com.toku345.Yank`, and refuses an accidental downgrade. Use `--no-launch` to
install without starting Yank, or `--destination "$HOME/Applications/Yank.app"`
for a per-user installation. Yank must not be running during replacement.

The first switch from a Debug build to the installed app may require removing
Yank from **System Settings > Privacy & Security > Accessibility** and granting
access again.

### Public Releases

Public distribution is currently deferred until Yank has external users; see
[Issue #53](https://github.com/toku345/Yank/issues/53). The tag workflow remains
dormant unless the `PUBLIC_RELEASES_ENABLED` repository variable is explicitly
set to `true`. Once enabled, pushing a semantic version tag such as `v0.1.0`
publishes a GitHub Release only after tests, Developer ID signing, notarization,
stapling, and Gatekeeper verification all succeed. Required secrets and the
release checklist are documented in [docs/releasing.md](docs/releasing.md).
Unsigned or Apple Development-signed builds are not published as release
artifacts.

### Keybindings

| Key | Action |
|-----|--------|
| Cmd+Shift+V | Open/close viewer |
| C-n / Down | Move selection down |
| C-p / Up | Move selection up |
| C-a | Jump to top |
| C-e | Jump to bottom |
| Return | Paste selected item |
| Delete | Delete selected history item |
| C-g / Escape | Close viewer |

### Data Deletion

Yank stores clipboard history in a SwiftData store. Use **Delete Selected** in the viewer to remove the
selected item, or **Clear All** to remove all saved history. This does not clear the current system
clipboard contents.

To reset all data outside the app:

```bash
rm -f ~/Library/Application\ Support/Yank.store*
```

### Security and Privacy Limitations

Yank stores restorable clipboard payloads in a SwiftData store. History is capped at 1,000
items and older entries are pruned, but retained entries may still include plaintext strings,
rich text, images, PDFs, and file URLs.

Yank applies owner-only permissions to the `Yank.store*` files on launch, plus best-effort OS
file protection where the volume supports it. This is defense-in-depth, not full database
encryption. SQLite sidecar files may be created after launch on first write and can remain at
default permissions until the next launch reapplies hardening.

While the user session is unlocked, same-user malware or processes with broad filesystem access
may still read retained clipboard payloads from the SwiftData store. Use **Delete Selected** or
**Clear All** to remove saved history; these actions do not clear the current system clipboard.
See [ADR 0006](docs/adr/0006-clipboard-history-at-rest-protection.md) and
[Issue #27](https://github.com/toku345/Yank/issues/27) for the at-rest protection tradeoffs and
remaining limitations.

## Architecture

See [PLAN.md](PLAN.md) for long-term product direction and phase outcomes, and
[docs/adr/](docs/adr/) for architecture decisions. Live delivery status is
tracked in [GitHub Issues](https://github.com/toku345/Yank/issues) and milestones.

## Acknowledgements

This project is inspired by and references the design of:

- [Clipy](https://github.com/Clipy/Clipy) (MIT License, Copyright (c) 2015-2018 Clipy Project) — clipboard monitoring, paste execution, hotkey registration, data model design
- [Maccy](https://github.com/p0deje/Maccy) (MIT License, Copyright 2025 Alex Rodionov) — self-paste suppression pattern, CGEvent configuration

## License

MIT
