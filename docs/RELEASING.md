# Releasing asdf GUI

This is the operational runbook for macOS packaging and GitHub Releases. Keep it synchronized with `.github/workflows/release.yml` and the scripts under `scripts/`.

## Distribution modes

asdf GUI is distributed outside the Mac App Store and remains **non-App-Sandboxed** so it can execute the user's local `asdf` binary and work with selected project directories.

The repository supports two release modes:

### Ad-hoc mode — no paid Apple Developer account required

When none of the Apple signing secrets are configured, the Release workflow automatically builds an **ad-hoc signed** app and DMG.

Ad-hoc signing provides bundle integrity, but it does **not** establish Apple trust and cannot be notarized. macOS Gatekeeper will therefore warn on first launch. The release is automatically marked as a GitHub **prerelease**, and artifact names include `adhoc`.

Users should install from the DMG, then use **Control-click / right-click `asdf GUI.app` → Open → Open** on first launch. After explicit approval, normal launches should work.

Do not describe an ad-hoc build as Apple-signed, notarized, or Gatekeeper-trusted.

### Developer ID mode — optional future upgrade

If all six documented Apple secrets are configured, the same workflow automatically switches to Developer ID mode:

- Developer ID Application signing;
- Hardened Runtime + secure timestamp;
- Apple `notarytool` notarization;
- stapling for the app and DMG;
- Gatekeeper verification;
- normal GitHub Release rather than prerelease.

If only some Apple secrets are configured, the workflow fails rather than silently choosing a weaker mode.

## Architecture artifacts

Release builds are architecture-specific:

```text
asdf-gui-X.Y.Z-macos-arm64-adhoc.dmg
asdf-gui-X.Y.Z-macos-x86_64-adhoc.dmg
```

or, after Developer ID credentials are configured:

```text
asdf-gui-X.Y.Z-macos-arm64-developer-id.dmg
asdf-gui-X.Y.Z-macos-x86_64-developer-id.dmg
```

Every release also includes `SHA256SUMS.txt`.

## Local ad-hoc package check

No Apple account is required:

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
  "dist/asdf-gui-0.0.0-dev-macos-$(uname -m)-adhoc.dmg"

bash scripts/verify-package.sh \
  "dist/asdf GUI.app" \
  "dist/asdf-gui-0.0.0-dev-macos-$(uname -m)-adhoc.dmg"
```

Normal CI runs this packaging verification on every pull request and push to `main`.

## Release triggers

The workflow supports two triggers.

### Standard tag trigger

```bash
git tag v0.1.0
git push origin v0.1.0
```

### Publish-branch trigger

A branch named exactly like this also triggers a release:

```text
publish/v0.1.0
```

This exists so automation that can create branches but cannot directly create Git tags can still publish a release. The workflow resolves the branch name to `v0.1.0`, and `gh release create --target` creates the release tag at that commit if necessary.

Use release/publish branches only intentionally. They are release triggers, not normal development branches.

## What the workflow does in ad-hoc mode

1. Validates `vMAJOR.MINOR.PATCH`.
2. Confirms that no Apple signing secrets are configured.
3. Builds independently on Apple Silicon and Intel runners.
4. Creates the `.app` bundle from the SwiftPM release executable.
5. Applies an ad-hoc Hardened Runtime signature (`SIGN_IDENTITY=-`).
6. Creates the drag-to-Applications DMG.
7. Verifies bundle metadata, the ad-hoc code signature, executable presence, icon, and DMG integrity.
8. Uploads both architecture artifacts.
9. Generates SHA-256 checksums.
10. Creates a GitHub prerelease with explicit Gatekeeper instructions.

No notarization or `spctl` trust assertion is attempted in this mode because those would be expected to fail without Developer ID trust.

## Optional Apple prerequisites

A future trusted/notarized release requires:

1. Apple Developer Program membership.
2. A **Developer ID Application** certificate exported as `.p12` plus its password.
3. An App Store Connect API key (`.p8`) with Key ID and Issuer ID for notarization.

Required GitHub Actions secrets:

| Secret | Purpose |
| --- | --- |
| `APPLE_DEVELOPER_ID_P12_BASE64` | Base64 Developer ID Application `.p12` |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | `.p12` export password |
| `APPLE_DEVELOPER_ID_APPLICATION_IDENTITY` | Exact codesigning identity |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64 App Store Connect API `.p8` |
| `APPLE_NOTARY_KEY_ID` | API Key ID |
| `APPLE_NOTARY_ISSUER_ID` | API Issuer ID |

All six must be present to enable Developer ID mode. Never commit certificates, private keys, passwords, or API credentials.

## Packaging details

The project stays SwiftPM-based. `scripts/build-app.sh` creates:

```text
asdf GUI.app/
  Contents/
    Info.plist
    MacOS/asdf-gui
    Resources/AppIcon.icns
```

Metadata:

- bundle identifier: `io.github.syjsion.asdf-gui`;
- minimum macOS: 14.0;
- release version: tag/branch version without the leading `v`;
- build number: GitHub Actions run number.

The App Icon is generated deterministically by `scripts/generate-app-icon.py` and converted with `iconutil`.

`scripts/create-dmg.sh` creates a compressed UDZO DMG containing the app plus an `/Applications` symlink.

## Signing and notarization details

`packaging/asdf-gui.entitlements` intentionally does not enable App Sandbox or Hardened Runtime exception entitlements.

Ad-hoc mode uses:

```text
codesign --options runtime --sign -
```

Developer ID mode uses:

```text
codesign --options runtime --timestamp --sign <Developer ID Application identity>
```

`scripts/notarize.sh` uses `xcrun notarytool submit ... --wait` and `xcrun stapler`. Do not reintroduce deprecated `altool`.

## First-launch behavior for ad-hoc builds

Because the downloaded DMG/app receives the quarantine attribute and the app is not notarized, double-clicking may be blocked by Gatekeeper.

Preferred user flow:

1. Open the DMG.
2. Drag **asdf GUI** to Applications.
3. In Applications, Control-click/right-click **asdf GUI**.
4. Choose **Open**.
5. Confirm **Open** in the warning dialog.

This preserves macOS security prompts and requires explicit user approval. Do not instruct users to globally disable Gatekeeper.

## Troubleshooting

Verify an ad-hoc package:

```bash
codesign --verify --deep --strict --verbose=4 "asdf GUI.app"
hdiutil verify "asdf-gui-X.Y.Z-macos-arm64-adhoc.dmg"
```

Developer ID identity inspection:

```bash
security find-identity -v -p codesigning
```

Notarization log lookup:

```bash
xcrun notarytool log <submission-id> \
  --key <AuthKey.p8> \
  --key-id <key-id> \
  --issuer <issuer-id>
```

For ad-hoc releases, Gatekeeper rejection is expected until the user explicitly approves the app. For Developer ID mode, Gatekeeper rejection is a release failure and must be investigated before publication.
