# ADR 0002: Self-Paste Suppression via Custom Pasteboard Type

## Status

Accepted

## Context

When the user selects a clipboard history item in Yank, the app writes it to `NSPasteboard` and simulates Cmd+V. The clipboard monitor then detects a `changeCount` change and must distinguish this self-triggered write from external clipboard activity. Without suppression, the app recaptures its own paste, creating duplicate history entries.

PR #4 used `OSAllocatedUnfairLock<Int>` (`skipLock`) shared between `PasteEngine` and `ClipboardMonitor`:
- PasteEngine set `skipLock` to `Int.max` before writing, then updated to the actual `changeCount` after
- ClipboardMonitor skipped any `changeCount <= skipValue`

This worked but had drawbacks:
- Tight coupling: PasteEngine needed a direct reference to ClipboardMonitor's lock
- Concurrency complexity: required an unfair lock for thread safety
- Implicit protocol: correct behavior depended on precise ordering of lock operations

[Maccy](https://github.com/p0deje/Maccy) (MIT License) uses a different approach: a custom `NSPasteboard.PasteboardType` marker written alongside the pasted data. The monitor checks for this marker and skips capture when present.

## Decision

Replace `skipLock` with a custom pasteboard type marker:

```swift
extension NSPasteboard.PasteboardType {
    static let fromYank = NSPasteboard.PasteboardType("com.toku345.Yank.self-paste")
}
```

**Write side (PasteService):** After writing all clipboard types, append `.fromYank` marker:
```
pasteboard.setString("", forType: .fromYank)
```

**Read side (ClipboardMonitor):** On changeCount change, check for marker presence:
```
if pasteboard items contain .fromYank → skip capture
```

The marker persists on the pasteboard until another app writes new content, which is the correct behavior (no further captures until external activity).

This pattern is inspired by Maccy's `.fromMaccy` implementation. As this is a design pattern adoption (not code copying), attribution is via code comment at the definition site.

## Consequences

**Positive:**
- PasteService and ClipboardMonitor are fully decoupled — no shared state, no lock, no reference to each other
- Simpler mental model: the pasteboard itself carries the suppression signal
- No concurrency primitives needed

**Negative:**
- The marker is visible to other apps reading the pasteboard (via `NSPasteboard.types`). This is benign — apps ignore unknown types.

**Risks:**
- If a future macOS version changes pasteboard behavior (e.g., stripping unknown types), the marker could be lost. This is unlikely given longstanding NSPasteboard behavior, but worth noting.
