# ADR 0006: Clipboard History At-Rest Protection

## Status

Accepted

## Context

Yank persists clipboard history with SwiftData:

- `AppCoordinator` creates the store with `ModelConfiguration("Yank", schema: schema)`.
- Repository guidance and `README.md` document the reset path as `~/Library/Application Support/Yank.store*`.
- `ClipItem` stores restorable clipboard payloads directly: plaintext strings, RTF, RTFD, HTML, PDF, TIFF-normalized image data, and file URL strings.
- `project.yml` disables App Sandbox because global hotkeys and synthetic paste rely on Carbon and CGEvent behavior outside the sandbox.

Issue #27 describes the security risk: clipboard history is stored as an unencrypted SwiftData/Core Data SQLite store. Any process or user with filesystem access to the user's home directory can inspect retained clipboard history at rest.

PR #37 reduced the retention risk for Issue #28 by capping history at 1,000 entries and pruning older `ClipItem` rows. This bounds the amount of retained plaintext, but it does not encrypt the retained rows and it does not protect the newest or most sensitive copied values.

This ADR is a pre-implementation spike. It does not change capture, persistence, paste behavior, package dependencies, GitHub issues, or runtime data.

## Decision

Use a staged, dependency-free mitigation first:

1. Keep SwiftData as the clipboard history store for Phase 1 and early Phase 2.
2. Add a small store-hardening implementation slice that applies best-effort macOS file protection and owner-only file permissions to the SwiftData store family (`Yank.store*`) and verifies the resulting attributes.
3. Treat file protection and POSIX permissions as defense-in-depth only, not as full database encryption.
4. Continue reducing plaintext exposure with product controls: retention cap, external capture skip markers, manual deletion, clear-all, and later sensitive-item deletion flows.
5. Defer SQLCipher or another encrypted-store dependency until the project explicitly accepts an external dependency and migration cost.
6. Defer Keychain-backed payload storage to a later sensitive-item slice, after Yank has reliable sensitive classification or explicit user marking.

The first implementation slice may harden the current SwiftData store family, but it is not required to preserve the existing store if a cleaner destructive redesign is chosen.

This means Issue #27 should not be closed by file protection alone unless the issue acceptance criteria are narrowed to "best-effort OS file protection." A plaintext scan of the SQLite store while the user session is unlocked may still reveal clipboard content.

## Migration Policy

Yank is currently a personal project, so early security hardening may use destructive local data changes when that produces a simpler and safer design.

Existing local clipboard history may be discarded during at-rest protection work. Backward-compatible migration from plaintext stores is not required for early security slices. Store reset, schema replacement, or rebuilding the local SwiftData store is acceptable when it materially reduces complexity, avoids preserving insecure plaintext rows, or enables a cleaner storage model.

This policy does not relax the privacy boundary: implementation and verification must not inspect, collect, log, or publish the user's real clipboard contents, existing SwiftData store contents, or private runtime logs.

## Options Considered

| Option | Effectiveness | Implementation cost | External dependency | UX impact | Verification |
| --- | --- | --- | --- | --- | --- |
| macOS file protection and owner-only permissions | Helps against offline or locked-device access on volumes that support file protection; restricts other Unix users. Does not stop same-user malware after unlock, root, or processes that can read the file while available. | Low to medium. Need locate the store family, apply attributes to `.store`, WAL, SHM, and future sidecars, and reapply on launch. | None. | Low. May introduce startup or locked-state edge cases if a protected file cannot be opened. | Check `URLResourceKey.fileProtectionKey`, `URLResourceKey.volumeSupportsFileProtectionKey`, and POSIX mode on temporary test stores. Manual lock-state behavior remains platform-dependent. |
| SwiftData standard configuration only | No meaningful at-rest protection beyond default filesystem and volume encryption behavior. | Low. | None. | None. | Confirm store is created and plaintext can be read in a controlled test store. |
| Keychain for sensitive payloads only | Stronger for small values that are classified sensitive or explicitly marked. Leaves ordinary history and metadata in SwiftData. Not suitable for all arbitrary rich clipboard payloads. | Medium to high. Requires payload indirection, lifecycle sync, deletion, migration, failure handling, and classification UX. | None, uses Security framework. | Medium. Keychain failures can affect restore/paste. Classification mistakes can leave secrets in SQLite. | Unit tests around payload references; integration tests with temporary Keychain item namespace; controlled canary scan verifies sensitive payload bytes are absent from SwiftData. |
| SQLCipher or equivalent encrypted SQLite store | Strongest fit for full-history at-rest encryption. Can make SQLite files unreadable without the encryption key. | High. Requires dependency acceptance, key management, SwiftData/Core Data compatibility work, migration, CI setup, and recovery behavior. | Yes. Conflicts with the current zero-runtime-dependency policy unless explicitly accepted. | Medium. Unlock/key failures need user-facing handling. Potential performance and migration impact. | Copy a controlled canary into a test store and verify `strings`/hex scans do not reveal it; migration and wrong-key tests. |
| No at-rest change; rely on retention, skip markers, and delete UI | Reduces volume and lifetime of retained plaintext but does not protect retained data at rest. | Low. | None. | Low to positive if deletion UI is good. | Tests for pruning, skip markers, delete item, clear all, and auto-delete flows. Does not satisfy at-rest protection by itself. |

## Apple SDK Notes

Checked against the local Xcode 26.4 macOS SDK:

- Foundation exposes `NSFileProtectionKey`, `NSURLFileProtectionKey`, `NSURLVolumeSupportsFileProtectionKey`, and `NSURLFileProtectionCompleteUnlessOpen` on macOS.
- The SDK comment for `NSURLFileProtectionCompleteUnlessOpen` describes encrypted on-disk storage where a file opened while unlocked can remain accessible after lock, but cannot be reopened until unlock.
- Core Data exposes `NSPersistentStoreFileProtectionKey` as an iOS-only persistent store option; it is unavailable on macOS. Therefore, this ADR does not assume SwiftData can request persistent-store file protection through a standard Core Data store option on macOS.
- Security framework `SecItem` supports generic password items and data-protection keychain usage on macOS, including `kSecUseDataProtectionKeychain` for `kSecAttrAccessible` without synchronizable items.

Unconfirmed:

- The exact SwiftData sidecar file set and protection inheritance behavior should be verified in a temporary store during implementation.
- Whether all target user volumes support file protection must be checked at runtime with `volumeSupportsFileProtectionKey`.
- The user-visible behavior when Yank starts while the store is protected and unavailable needs manual testing.

## Consequences

Positive:

- Preserves the current zero external dependency policy.
- Gives an immediate, reviewable implementation slice with measurable filesystem attributes.
- Avoids prematurely committing to SQLCipher before migration and key-management design are understood.
- Allows early security slices to avoid compatibility migration work when local data reset is simpler and safer.
- Keeps the path open for stronger sensitive-item handling in Phase 3.

Negative:

- Does not provide full database encryption.
- Does not satisfy a "no plaintext visible to `strings` while unlocked" requirement for all clipboard history.
- Local clipboard history may be lost during security upgrades.
- Requires clear documentation so users do not mistake file protection for protection against active same-user malware.
- Store sidecars must be handled carefully; protecting only the main `.store` file is insufficient.

## Security Limitations

- Clipboard payloads retained in SwiftData remain logically plaintext to Yank and may be readable by same-user malware while the user session is unlocked.
- App Sandbox is disabled by design, so Yank's store is not isolated in an app container.
- File protection depends on the filesystem volume supporting the protection attribute.
- POSIX owner-only permissions do not protect against the same Unix user, root, backups, compromised developer tools, or processes with broad filesystem access.
- Retention cap limits the number of stored items but does not reduce exposure for the newest retained entries.
- Skip markers reduce capture of known sensitive external clipboard formats only after those markers are implemented and only for apps that publish such markers.
- Keychain storage protects only payloads routed there; classification false negatives remain a risk.

## Verification Plan

For the first implementation slice:

1. Use a temporary SwiftData store or controlled test fixture, not the user's real clipboard history or existing store.
2. Create a canary `ClipItem` in the temporary store.
3. Apply file protection and owner-only permissions to the store family.
4. Verify the main store and sidecars have owner-only permissions where supported.
5. Verify `fileProtectionKey` on files where the volume reports `volumeSupportsFileProtectionKey == true`.
6. Verify the app can reopen the temporary store after hardening.
7. Document that `strings` scanning while unlocked is expected to reveal plaintext until a true encrypted-store or Keychain-payload design is implemented.

For later stronger options:

- Keychain-sensitive-payload slice: verify sensitive canary payloads are absent from SwiftData bytes and deleted from Keychain when the corresponding history item is deleted.
- SQLCipher slice: verify canary payloads are absent from the SQLite file and sidecars, verify wrong-key behavior, and verify migration from the current plaintext store.

## Follow-Up Implementation Slices

1. Store hardening service:
   - Add a small service that locates `~/Library/Application Support/Yank.store*`.
   - Apply `NSFileProtectionCompleteUnlessOpen` or the closest supported value.
   - Apply owner-only file permissions.
   - Reapply on launch to cover WAL/SHM sidecars.
   - Reset or rebuild the local store if that is simpler than preserving existing plaintext files.
   - Add tests using a temporary store path.

2. Sensitive capture avoidance:
   - Implement known external skip markers such as password-manager concealed clipboard types.
   - Add tests that marker-bearing pasteboard snapshots are skipped.

3. Deletion controls:
   - Add delete selected item and clear-all UI.
   - Add paste-then-delete behavior for explicitly sensitive items.
   - Add tests that SwiftData rows and any future sidecar payloads are deleted together.

4. Keychain-backed sensitive payload spike:
   - Define a payload reference model in SwiftData.
   - Store only explicitly sensitive, small payloads in Keychain.
   - Keep metadata minimal and non-sensitive in SwiftData.
   - Prefer a clean model over compatibility migration from existing plaintext rows.
   - Define failure behavior when Keychain data is missing or inaccessible.

5. Full encrypted-store spike:
   - Evaluate SQLCipher or another encrypted SQLite approach against SwiftData/Core Data compatibility.
   - Decide whether the security benefit justifies adding a runtime dependency.
   - Define key storage, destructive store replacement, backup, and recovery behavior before implementation.
