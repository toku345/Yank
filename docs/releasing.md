# Release Process

> [!IMPORTANT]
> Public distribution is deferred until Yank has external users; see
> [Issue #53](https://github.com/toku345/Yank/issues/53). Keep the
> `PUBLIC_RELEASES_ENABLED` GitHub Actions repository variable unset or set to a
> value other than `true` until that decision is revisited. The release job is
> skipped while the variable is disabled.

Yank uses two separate Release paths:

- A local Production install uses an Apple Development identity and installs the
  app on the developer's Mac.
- A public GitHub Release uses a Developer ID Application identity and Apple's
  notary service. The workflow never publishes an unsigned or development-signed
  application.

## Local Production Install

Complete `docs/dev-signing.md`, then run:

```bash
./scripts/install-production.sh
```

This archives the `Yank-Production` scheme with the Release configuration,
verifies the result, atomically replaces `/Applications/Yank.app`, and launches
the installed application. The first Debug-to-installed transition may require
granting Accessibility access again.

## Public Release Prerequisites

Public distribution outside the Mac App Store requires membership in the Apple
Developer Program, a Developer ID Application certificate, hardened runtime,
and notarization. Yank already enables hardened runtime; the workflow supplies
the distribution identity and submits the signed app with `notarytool`.

Configure these GitHub Actions repository secrets before pushing a release tag:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` file, including its private key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` file |
| `APPLE_TEAM_ID` | Apple Developer Program Team ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Base64-encoded App Store Connect API `.p8` key authorized for notarization |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer ID |

Treat the certificate, private key, passwords, and API key as secrets. Rotate
them immediately if they are exposed.

After all prerequisites are ready and Issue #53 is intentionally resumed, set
the GitHub Actions repository variable `PUBLIC_RELEASES_ENABLED` to exactly
`true`. This is a separate publication gate; setting secrets alone does not
enable releases.

## Versioning

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` are the
version source of truth. Before releasing:

1. Set `MARKETING_VERSION` to the semantic version, for example `0.1.0`.
2. Increment `CURRENT_PROJECT_VERSION` for every shipped build.
3. Merge the version change and release notes to `main`.
4. Confirm CI succeeds on that commit.

The tag workflow rejects tags that do not match `vMAJOR.MINOR.PATCH`, do not
point to a commit on `main`, do not match `MARKETING_VERSION`, or use an invalid
build number. Configure a GitHub tag rule for `v*` that prevents tag updates and
deletions.

## Publish

Only after enabling public releases, create and push an annotated tag from the
verified `main` commit:

```bash
git switch main
git pull --ff-only
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

The tag starts `.github/workflows/release.yml`, which:

1. validates the tag and project version;
2. runs lint and tests;
3. imports the Developer ID certificate into a temporary keychain;
4. creates a Universal Release archive without code coverage or
   `get-task-allow`;
5. verifies the Developer ID signature and hardened runtime;
6. submits the app for notarization and staples the ticket;
7. verifies Gatekeeper acceptance; and
8. publishes the app ZIP, dSYM ZIP, and SHA-256 checksums as a GitHub Release.

Any failed signing, notarization, or verification step stops the workflow before
publication. If the source commit is unchanged, rerun the failed workflow for
the same immutable tag. If a source change is required, increment the version
and build number and create a new tag; never move an existing release tag.

Apple references:

- [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/)
- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
