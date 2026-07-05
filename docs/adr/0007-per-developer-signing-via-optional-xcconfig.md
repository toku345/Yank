# ADR 0007: Per-Developer Code Signing via Optional xcconfig Include

## Status

Accepted

## Context

Debug builds were ad-hoc signed (`project.yml` sets no signing identity), which makes
the code signature's designated requirement `cdhash`-based. macOS TCC keys the
Accessibility grant on the designated requirement, so every rebuild produced a
"new app" and silently revoked the permission — `CGEvent.post` paste stopped
working after each build (issue #11, also recorded as a root cause in ADR 0003).

Signing with a real Apple Development certificate yields a certificate-based
designated requirement (`identifier + certificate leaf`), which is stable across
rebuilds. The problem is where to put the per-developer `DEVELOPMENT_TEAM`:

1. **`DEVELOPMENT_TEAM` in `project.yml`** — committed file; leaks a personal
   Team ID to the public repo and breaks CI (`macos-15` runners have no such
   certificate). Rejected.
2. **Xcode UI (Signing & Capabilities)** — `.xcodeproj` is an XcodeGen artifact;
   every `xcodegen generate` wipes the setting. Rejected.
3. **Self-signed certificate** — avoids the Apple ID requirement but needs a
   non-standard manual Keychain Access procedure and is useless for any future
   distribution. Rejected.

## Decision

Inject signing settings through a two-level xcconfig indirection, applied to the
**Debug configuration only**:

- `project.yml` `configFiles` maps `Debug` → `SupportingFiles/Base.xcconfig`
  (committed, survives `xcodegen generate`).
- `Base.xcconfig` contains only `#include? "Local.xcconfig"` — an *optional*
  include that silently no-ops when the file is absent.
- `SupportingFiles/Local.xcconfig` (gitignored) holds the per-developer
  `DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE` / `CODE_SIGN_IDENTITY`.

Setup steps live in `docs/dev-signing.md`.

## Consequences

**Positive:**

- Accessibility permission survives rebuilds; the remove/re-add workaround is
  no longer part of the normal dev loop.
- CI and fresh clones need no change: without `Local.xcconfig` the optional
  include resolves to nothing and builds stay ad-hoc signed, exactly as before.
- Personal Team IDs never enter the repository.
- Debug-only scoping keeps personal development identities out of Release and
  archive builds.

**Negative:**

- One-time per-developer setup (Apple ID in Xcode, certificate, `Local.xcconfig`).
- Real signing activates hardened runtime (ad-hoc signing silently disables it
  despite `ENABLE_HARDENED_RUNTIME: true`); Xcode injects
  `com.apple.security.get-task-allow` into Debug builds so debugging still works.

**Risks:**

- Apple Development certificates expire after ~1 year; renewal changes the
  certificate and requires re-granting Accessibility once.
- If `#include?` is ever downgraded to `#include`, or `configFiles` points at
  `Local.xcconfig` directly, every machine without the gitignored file — all of
  CI — fails to build. The optional include is load-bearing.
