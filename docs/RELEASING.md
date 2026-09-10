# Releasing asdf GUI

This document describes the macOS distribution pipeline. Keep it in sync with `.github/workflows/release.yml` and the scripts under `scripts/`.

## Distribution model

asdf GUI is distributed outside the Mac App Store as a Developer ID-signed and Apple-notarized `.dmg`.

The application intentionally remains **non-App-Sandboxed** because it needs to invoke the user's local `asdf` executable and work with project directories selected by the user. The release does enable the Hardened Runtime during code signing.

The repository remains a Swift Package rather than adding an Xcode project purely for packaging. `scripts/build-app.sh` creates the standard macOS `.app` bundle around the SwiftPM release executable.

Release artifacts are architecture-specific:

- `asdf-gui-X.Y.Z-macos-arm64.dmg`
- `asdf-gui-X.Y.Z-macos-x86_64.dmg`
- `SHA256SUMS.txt`

## Local unsigned/ad-hoc package check

A Developer ID certificate is not required to verify the bundle/DMG assembly locally:

```bash
rm -rf dist
VERSION=0.0.0-dev \
BUILD_NUMBER=1 \
OUTPUT_DIR="$PWD/dist" \
SIGN_IDENTITY=- \
bash scripts/build-app.sh

SIGN_IDENTITY=- \
bash scripts/create-dmg.sh \
  "dist/asdf GUI.app" \
  "dist/asdf-gui-0.0.0-dev-macos-$(uname -m).dmg"

bash scripts/verify-package.sh \
  "dist/asdf GUI.app" \
  "dist/asdf-gui-0.0.0-dev-macos-$(uname -m).dmg"
```

The normal GitHub Actions CI performs this ad-hoc packaging check on every pull request and push to `main`.

## Apple prerequisites

A signed public release requires:

1. An Apple Developer Program account.
2. A **Developer ID Application** certificate exported as a `.p12` together with its export password.
3. An App Store Connect API key (`.p8`) that can authenticate to the Apple notary service, plus its Key ID and Issuer ID.

Do not commit any certificate, private key, password, or API credential to this repository.

## Required GitHub Actions secrets

Configure these repository or environment secrets before creating a release tag:

| Secret | Purpose |
| --- | --- |
| `APPLE_DEVELOPER_ID_P12_BASE64` | Base64-encoded Developer ID Application `.p12` |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_DEVELOPER_ID_APPLICATION_IDENTITY` | Exact codesigning identity, e.g. `Developer ID Application: Name (TEAMID)` |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64-encoded App Store Connect API `.p8` private key |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API Key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect Issuer ID |

Example commands for producing the base64 values on macOS without line wrapping:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
base64 -i AuthKey_ABC123XYZ.p8 | pbcopy
```

Store the resulting values in GitHub Actions secrets; never paste them into source files, issues, PRs, or CI logs.

## Release process

Public releases are tag-driven. Use an exact semantic version tag:

```text
vMAJOR.MINOR.PATCH
```

For example:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The `Release` workflow then:

1. Validates the tag and required secrets.
2. Builds independently on Apple Silicon and Intel macOS runners.
3. Imports the Developer ID certificate into a temporary CI keychain.
4. Builds the release `.app` and signs it with Hardened Runtime + secure timestamp.
5. Submits a ZIP containing the app to `notarytool` and waits for Apple notarization.
6. Staples the notarization ticket to the app and performs a Gatekeeper assessment.
7. Creates and signs a compressed DMG containing the app plus an `/Applications` shortcut.
8. Submits the DMG to `notarytool`, staples its ticket, and verifies the package.
9. Uploads both architecture-specific DMGs as workflow artifacts.
10. Generates SHA-256 checksums and creates the GitHub Release with generated release notes.

The workflow intentionally fails instead of creating an unsigned release if any Apple credential is missing.

## Signing details

`packaging/asdf-gui.entitlements` is intentionally empty. The app is **not sandboxed** and currently requires no Hardened Runtime exception entitlements.

`build-app.sh` signs the app with:

```text
codesign --options runtime --timestamp
```

For CI package verification without Apple credentials, the same script uses an ad-hoc signature (`SIGN_IDENTITY=-`). Ad-hoc packages are only build/test artifacts and must not be published as releases.

## Notarization details

`scripts/notarize.sh` uses `xcrun notarytool submit ... --wait` with an App Store Connect API key. The workflow notarizes and staples both the app and the final DMG.

Do not switch back to `altool`; Apple's current notarization service requires `notarytool` or the Notary API for custom workflows.

## Version metadata

The release tag `vX.Y.Z` becomes `CFBundleShortVersionString = X.Y.Z`.

`CFBundleVersion` is the GitHub Actions run number. Local builds may set `BUILD_NUMBER` manually.

The bundle identifier is:

```text
io.github.syjsion.asdf-gui
```

The deployment target remains macOS 14.0 even though CI/release builders may run newer macOS versions.

## App icon

The release icon is generated deterministically by `scripts/generate-app-icon.py` into the standard macOS iconset sizes, then converted to `AppIcon.icns` with `iconutil`. This avoids checking generated binary icon assets into Git while keeping packaging reproducible and dependency-free.

If the visual identity changes later, keep the generator or replace it with committed design-source assets plus a reproducible export process. Update this document either way.

## Troubleshooting

If signing fails, inspect available identities in the temporary/local keychain:

```bash
security find-identity -v -p codesigning
```

If notarization fails, use the submission ID printed by `notarytool` to retrieve the log:

```bash
xcrun notarytool log <submission-id> \
  --key <AuthKey.p8> \
  --key-id <key-id> \
  --issuer <issuer-id>
```

If Gatekeeper assessment fails after successful notarization:

```bash
codesign --verify --deep --strict --verbose=4 "asdf GUI.app"
spctl --assess --type execute --verbose=4 "asdf GUI.app"
xcrun stapler validate "asdf GUI.app"
```

Do not work around signing or notarization failures by disabling Hardened Runtime or publishing an unsigned DMG. Diagnose the failing component instead.
