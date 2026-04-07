# ADR 0003: Paste Flow Delay Removal and Staged Verification

## Status

Accepted

## Context

PR #4's paste flow used two hardcoded delays:
- **200ms** between hiding the panel and calling PasteEngine
- **50ms** between writing to pasteboard and simulating Cmd+V

These delays were introduced during trial-and-error debugging of a paste failure. The root cause turned out to be:

1. **Incorrect CGEvent configuration** — `.hidSystemState` + `.cghidEventTap` silently failed on macOS 26. The fix was switching to `.combinedSessionState` + `.cgSessionEventTap` with `NX_NONCOALESCED` flag.
2. **Stale Accessibility permissions** — Each debug build changed the binary, silently invalidating macOS's Accessibility permission grant. Re-granting permissions resolved the issue.

Neither root cause was related to timing. The delays were artifacts of debugging, added before the real causes were identified. With the correct CGEvent configuration and proper Accessibility permission checking (ADR 0001), the delays may be unnecessary.

## Decision

Remove both hardcoded delays in the initial implementation and verify paste behavior through staged testing:

**Stage 1: No delays (baseline)**
```text
writeToPasteboard(item)  →  hide()  →  simulateCmdV()
```
All three calls execute synchronously on the main thread.

**Stage 2: If paste fails to reach target app**

Defer `simulateCmdV()` by one RunLoop cycle via `DispatchQueue.main.async`:
```swift
writeToPasteboard(item)
hide()                    // NSApp.hide(nil) — triggers focus return
DispatchQueue.main.async {
    simulateCmdV()        // executes after hide's side effects are processed
}
```
This ensures `NSApp.hide(nil)` completes its event processing (including focus transfer to the previous app) before the CGEvent is posted. Unlike a fixed delay, it waits exactly one RunLoop iteration — the minimum possible deferral.

Note: `NSWorkspace.didActivateApplicationNotification` was considered but rejected because:
- ViewerPanel uses `.nonactivatingPanel`, so the previous app may never be deactivated — the notification may not fire
- `hide()` and focus return can occur synchronously, causing the notification to be missed if the observer is registered after `hide()`
- No mechanism to identify which app should receive Cmd+V, risking delivery to the wrong app

**Stage 3: If RunLoop deferral is insufficient**

Add a minimal fixed delay (start at 50ms, increase if needed) as a pragmatic fallback. Document the specific failure scenario that required it.

## Consequences

**Positive:**
- Eliminates 250ms of unnecessary latency if delays prove unneeded
- Stage 2 (RunLoop deferral) is the minimum possible delay — one iteration, not a guessed duration
- Each stage is testable independently and progressively adds latency

**Negative:**
- Requires manual testing on real hardware (paste simulation cannot be unit tested)
- May need to go through multiple stages before finding a stable solution

**Risks:**
- Stage 1 may not work on all machines. Stage 2 mitigates by deferring one RunLoop cycle. Stage 3 provides a pragmatic fixed-delay fallback if both fail.
