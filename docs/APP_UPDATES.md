# In-app app updates

Starting with v0.7.0, asdf GUI can download, verify, install, and relaunch an app update without sending the user to a browser for the normal path.

## Release discovery

- Continue querying the GitHub Releases list instead of `/releases/latest` because ad-hoc builds are published as prereleases.
- Compare versions semantically and include prereleases.
- Select only the DMG matching the architecture of the running app (`macos-arm64` or `macos-x86_64`).
- The original browser Release page remains a fallback action.

## Trust and verification

In-app installation is fail-closed.

1. The asset URL must be HTTPS and belong to `github.com/syjsion/asdf-gui/releases/download/...`.
2. The asset filename must match the release metadata, current architecture, and `.dmg` suffix.
3. GitHub's Release asset must expose a `sha256:` digest.
4. The downloaded DMG is hashed locally with CryptoKit and must match that digest exactly.
5. `hdiutil verify` must accept the DMG.
6. The DMG is mounted read-only and without Finder browsing.
7. The contained app must use bundle identifier `io.github.syjsion.asdf-gui` and the exact target semantic version.
8. `codesign --verify --deep --strict` must accept the staged app. For ad-hoc releases this checks bundle/signature integrity, not Apple Developer identity; the SHA-256 Release digest remains the download trust anchor.

Never disable Gatekeeper, strip quarantine attributes, use `curl | sh`, accept an update without a digest, or install an asset from another repository.

## Replacement model

The running app is never overwritten directly from the network.

- Download into the user cache.
- Verify the DMG and copy the verified `.app` into a staging directory.
- Generate a small local replacement helper from source-controlled constant text.
- Pass all paths as positional shell arguments; never interpolate paths into shell source.
- The helper waits for the current app process to exit, moves the old app to a temporary backup, copies the staged app with `/usr/bin/ditto`, and relaunches the target.
- If replacement fails, remove any partial new target, restore the backup, and try to reopen the old app.

The helper must not contain network access, `sudo`, `xattr`, package-manager calls, or arbitrary downloaded script execution.

## Installation location

The updater only self-replaces when the current bundle is a normal writable `.app` location. Refuse in-app replacement when the app is App Translocated, running directly from a read-only DMG, or its parent directory is not writable. In those cases, explain the limitation and keep the Release-page fallback available.

## UX

- Checking remains automatic when About opens and manual from the visible Settings & Tools page.
- Downloading and verification happen only after explicit user action.
- Installation requires a second explicit `Install and Relaunch` confirmation.
- Do not install while an asdf mutation is active.
- Show Download/Verify/Ready/Failure states in both English and Simplified Chinese.

## Tests

Keep regression coverage for:

- semantic version/release selection;
- architecture-specific asset selection;
- digest and size metadata propagation;
- official-repository URL validation;
- SHA-256 digest normalization and known-file hashing;
- generated helper constraints (positional paths, backup restore, no network/sudo/quarantine bypass).

Release CI still must build and verify both arm64 and x86_64 DMGs before publishing.
