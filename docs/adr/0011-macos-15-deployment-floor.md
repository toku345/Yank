# ADR 0011: Raise the Deployment Floor to macOS 15 Sequoia

## Status

Accepted

## Context

Yank originally targeted macOS 14 Sonoma. However, no part of the toolchain
ever exercised a macOS 14 runtime: CI runs on GitHub's `macos-15` runner and
local development uses newer OS releases. The claimed floor was therefore an
unverified support surface.

This gap became concrete with the Phase 2 snippet models (ADR 0010). Early
SwiftData releases shipped with macOS 14.x had documented instability around
required to-one relationships during cascade deletion, and issue #67 asked for
a one-off verification of the folder cascade-delete path on a real macOS 14
machine before shipping snippet deletion UI — a verification burden that would
recur for every SwiftData-sensitive change.

macOS 14 was released in September 2023 and is near the end of Apple's usual
security-update window. The hardware supported by macOS 15 is nearly identical
to macOS 14's, so raising the floor excludes only a small set of circa-2018
Intel Macs.

## Decision

Set the deployment target to macOS 15 Sequoia (`MACOSX_DEPLOYMENT_TARGET =
15.0` via `project.yml`). Update `PLAN.md`, `README.md`, and `CLAUDE.md` to
state the new floor.

Close issue #67 as obsolete: with macOS 15 as the floor, the CI runner OS and
the minimum supported OS coincide, so the cascade-delete path is exercised on
a supported runtime by the existing test suite.

## Consequences

Positive:

- The supported floor matches what CI (`macos-15`) actually verifies; no more
  claimed-but-untested OS surface.
- SwiftData behavior validated by the test suite is representative of the
  oldest supported runtime.
- Newer SwiftUI/SwiftData APIs (macOS 15 era) can be adopted without
  availability guards.

Negative:

- Users on macOS 14-only hardware (a small set of older Intel Macs) are
  excluded. No such users are known today; Yank has no public release yet.
- If a future distribution goal requires macOS 14 support, this decision must
  be revisited together with a real macOS 14 verification strategy.

The optional `Snippet.folder` relationship introduced for cascade processing
(ADR 0010) remains correct regardless of this change: it addresses current
SwiftData runtime behavior, not a macOS 14-specific defect.
