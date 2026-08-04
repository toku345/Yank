# ADR 0014: Adopt macOS 26 as the Development and CI Baseline

## Status

Accepted

## Context

Yank is not publicly distributed, and all machines currently used to develop
and run it use macOS 26. Continuing to target macOS 15 would preserve an
untested support surface without serving a known user.

The mismatch also became an engineering problem on macOS 26: view and
controller tests that repeatedly replaced a SwiftData container while mounted
SwiftUI content from the preceding repetition was being dismantled could
terminate the test process on a later iteration. Production opens the complete
Yank schema once and retains that container for the application's lifetime, so
the test fixture did not represent the lifecycle it was intended to exercise.

## Decision

Adopt macOS 26 Tahoe as Yank's deployment, development, and CI baseline. Set
`MACOSX_DEPLOYMENT_TARGET` to 26.0, require Xcode 26 or later, and run all macOS
GitHub Actions jobs on `macos-26`. The primary CI job records the macOS, Xcode,
and Swift versions in its log.

Tests that exercise app-integrated views or controllers must use an in-memory
container built from `YankSchema.current` and retain it for at least as long as
the mounted UI. Repetition tests for the viewer controller share one canonical
container and reset its stored data between cases, matching production's
single-container lifecycle. Focused model, service, or state tests may continue
to use the smallest schema needed for their contract, and migration tests
continue to define the historical schemas they verify.

Do not mask SwiftData lifecycle failures with retries, sleeps, timeouts, or
production-only workarounds. This decision supersedes ADR 0011.

## Consequences

Positive:

- Local development, the deployment target, and hosted CI exercise the same OS
  generation.
- App-integrated SwiftData tests follow the same schema ownership as production.
- Yank can adopt macOS 26 APIs without availability guards for older releases.

Negative:

- macOS 15 through macOS 25 are no longer supported.
- Contributors need Xcode 26 or later.
- The release workflow moves to the new runner even though public releases
  remain disabled.
