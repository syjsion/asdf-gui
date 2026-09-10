# asdf GUI

Native macOS GUI for [asdf](https://asdf-vm.com/), built with SwiftUI and Foundation.

The project keeps asdf and `.tool-versions` as the sources of truth. The app is a typed, visual control layer over the existing CLI rather than a reimplementation of version management.

## Requirements

- macOS 14+
- Xcode / Swift toolchain capable of building the Swift 5.10 package
- asdf installed locally

## Run from source

```bash
swift test
swift run asdf-gui
```

You can also open `Package.swift` directly in Xcode.

## Build a local macOS app / DMG

A Developer ID certificate is not required for a local ad-hoc packaging check:

```bash
rm -rf dist
VERSION=0.0.0-dev BUILD_NUMBER=1 OUTPUT_DIR="$PWD/dist" SIGN_IDENTITY=- \
  bash scripts/build-app.sh
SIGN_IDENTITY=- \
  bash scripts/create-dmg.sh \
    "dist/asdf GUI.app" \
    "dist/asdf-gui-0.0.0-dev-macos-$(uname -m).dmg"
```

The generated `.app` uses the same SwiftUI executable as `swift run`; the packaging scripts add the standard app bundle metadata, generated ICNS icon, ad-hoc or Developer ID signature, and DMG layout.

## Current features

- Detect asdf in common installation locations and allow a persisted custom executable path.
- Overview of asdf version, executable, plugins, and managed projects.
- Add/remove managed project folders and read their `.tool-versions` files without duplicating configuration into app storage.
- Preserve comments and ordered fallback chains when interpreting `.tool-versions`.
- Compare project requirements with installed asdf runtimes and show Installed, Missing, System, Local path, Plugin missing, or Unknown state.
- Install missing project runtimes with live stdout/stderr, cancellation, deterministic fallback planning, and post-success refresh.
- Browse installed/latest/available versions per plugin with search and Installed-only filtering.
- Install or uninstall individual runtime versions; uninstall always requires confirmation and shows managed-project usage impact.
- Set a project version through `asdf set` or a Home default through `asdf set -u`, with explicit configuration-impact confirmation.
- **Plugin Manager** window (`⌘⇧P`) for Add, Update, Update All, and Remove.
- Plugin removal impact inspection lists every installed runtime version that asdf will delete and every managed project that references the plugin before confirmation.
- **Diagnostics** window (`⌘⇧D`) for `asdf info`, `asdf where`, `asdf which`, and `asdf reshim`.
- Copy the current diagnostic output or generate a copyable diagnostic report containing the active asdf version, executable path, and `asdf info` output.
- Native **Set Runtime Version** window (`⌘⇧V`).
- Streaming/cancellable `Foundation.Process` command runner with no shell-string interpolation.
- Reproducible `.app` and DMG packaging from SwiftPM without requiring an Xcode project.
- Hardened Runtime / Developer ID signing and Apple `notarytool` automation for public releases.
- Tag-driven GitHub Release workflow producing separate Apple Silicon and Intel DMGs plus SHA-256 checksums.
- macOS GitHub Actions CI running tests and an ad-hoc app/DMG packaging verification.

## Distribution

Public releases are designed to be Developer ID-signed, Apple-notarized DMGs distributed outside the Mac App Store. The app intentionally does not enable App Sandbox because it needs to launch the user's local `asdf` executable and work with selected project directories.

Release tags use `vMAJOR.MINOR.PATCH`. The release workflow builds and notarizes both `arm64` and `x86_64` artifacts, then publishes them to GitHub Releases. Apple credentials are supplied only through GitHub Actions secrets.

See [`docs/RELEASING.md`](docs/RELEASING.md) for the signing/notarization secret names, local package verification, release flow, and troubleshooting.

## Development

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before making architectural changes or using Codex for follow-up development. It documents architecture boundaries, command contracts, destructive-action policies, project/version/plugin semantics, diagnostics behavior, distribution policy, roadmap status, and a reusable Codex working agreement.
