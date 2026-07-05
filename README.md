# Yank

A clipboard manager for macOS, successor to [Clipy](https://github.com/Clipy/Clipy). Built with SwiftUI + SwiftData, no runtime dependencies.

## Features

### Implemented (Phase 1 MVP)

- **Clipboard history** — automatically captures text, RTF, HTML, PDF, images, and file URLs
- **Global hotkey** — Cmd+Shift+V to open/close the history viewer
- **Emacs keybindings** — C-n/C-p (up/down), C-a/C-e (jump to start/end), C-g (close)
- **Paste simulation** — select an item and press Return to paste via CGEvent Cmd+V
- **Self-paste suppression** — Yank's own paste operations are excluded from history
- **Duplicate detection** — consecutive identical clipboard contents are deduplicated
- **History deletion controls** — delete the selected history item or clear all saved history

### Planned

- **Snippet management** — folder-organized snippets with C-f/C-b tab switching (Phase 2)
- **Clipy snippet import** — import existing Clipy XML snippets (Phase 2)
- **Status bar icon** — MenuBarExtra for quick access and settings (Phase 3)
- **Sensitive value handling** — sensitive classification and auto-delete after paste (Phase 3)
- **Launch at login** — via SMAppService (Phase 3)
- **Search** — incremental search with C-s (Phase 3)

## Requirements

- macOS 14 Sonoma or later
- Xcode 15.0+
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

See [PLAN.md](PLAN.md) for the full development plan and [docs/adr/](docs/adr/) for architecture decision records.

## Acknowledgements

This project is inspired by and references the design of:

- [Clipy](https://github.com/Clipy/Clipy) (MIT License, Copyright (c) 2015-2018 Clipy Project) — clipboard monitoring, paste execution, hotkey registration, data model design
- [Maccy](https://github.com/p0deje/Maccy) (MIT License, Copyright 2025 Alex Rodionov) — self-paste suppression pattern, CGEvent configuration

## License

MIT
