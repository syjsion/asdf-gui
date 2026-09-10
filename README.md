# asdf GUI

Native macOS GUI for [asdf](https://asdf-vm.com/), built with SwiftUI and Foundation.

The project keeps asdf and `.tool-versions` as the sources of truth. The app is a typed, visual control layer over the existing CLI rather than a reimplementation of version management.

## Requirements

- macOS 14+
- asdf may already be installed, or asdf GUI can install the latest official macOS binary for you
- Xcode / a compatible Swift toolchain is only required when building from source

## First launch / asdf setup

If asdf GUI cannot find a usable `asdf` executable, the app opens a dedicated setup screen instead of showing empty runtime/plugin views.

The **Install asdf** action:

- queries the official `asdf-vm/asdf` GitHub latest-release API;
- selects the matching macOS archive for the current app architecture (`arm64` or `amd64`);
- requires and verifies the release asset's SHA-256 digest before extraction;
- installs the binary to `~/.local/bin/asdf` without `sudo` or Homebrew;
- verifies the downloaded executable with `asdf version` before activating it;
- persists that exact executable path so Finder-launched asdf GUI does not depend on your interactive shell `PATH`.

The installer does **not** edit `~/.zshrc`, `~/.bashrc`, or other shell startup files. Terminal use of asdf still requires the normal asdf shims PATH setup documented by asdf. You can also choose an existing executable manually from Settings.

## Run from source

```bash
swift test
swift run asdf-gui
```

You can also open `Package.swift` directly in Xcode.

## Download / distribution

The release pipeline supports two modes:

- **Ad-hoc prerelease** — requires no paid Apple Developer account. The app is ad-hoc signed for bundle integrity, but is not Apple-notarized or Gatekeeper-trusted. On first launch, use **Control-click / right-click the app → Open → Open**.
- **Developer ID release** — automatically enabled later if all documented Apple signing/notarization secrets are configured.

Both modes publish separate Apple Silicon (`arm64`) and Intel (`x86_64`) DMGs plus `SHA256SUMS.txt`.

See [`docs/RELEASING.md`](docs/RELEASING.md) for release triggers, first-launch instructions, optional Apple credentials, and troubleshooting.

## Build a local macOS app / DMG

No Apple Developer account is required:

```bash
rm -rf dist
VERSION=0.0.0-dev BUILD_NUMBER=1 OUTPUT_DIR="$PWD/dist" SIGN_IDENTITY=- \
  bash scripts/build-app.sh
SIGN_IDENTITY=- \
  bash scripts/create-dmg.sh \
    "dist/asdf GUI.app" \
    "dist/asdf-gui-0.0.0-dev-macos-$(uname -m)-adhoc.dmg"
```

The packaging scripts create the standard `.app` bundle, generated ICNS icon, ad-hoc or Developer ID signature, and drag-to-Applications DMG.

## Current features

- Detect asdf in common installation locations and allow a persisted custom executable path.
- Dedicated missing-asdf setup experience with verified one-click installation from official GitHub release assets.
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
- Reproducible `.app` and DMG packaging directly from SwiftPM.
- No-account ad-hoc GitHub prerelease workflow.
- Optional Developer ID + Hardened Runtime + Apple `notarytool` release path for the future.
- Separate Apple Silicon and Intel release artifacts with SHA-256 checksums.
- macOS GitHub Actions CI running tests and app/DMG package verification.

## Release triggers

Normal release tag:

```text
vMAJOR.MINOR.PATCH
```

Automation may alternatively create a branch named:

```text
publish/vMAJOR.MINOR.PATCH
```

The latter exists so tools that can create branches but not Git tags can still trigger the same Release workflow. Ad-hoc artifacts are automatically published as a GitHub prerelease and clearly include `adhoc` in their filenames.

## Development

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before making architectural changes or using Codex for follow-up development. It documents architecture boundaries, command contracts, destructive-action policies, project/version/plugin semantics, diagnostics behavior, bootstrap/install policy, release modes, roadmap status, and a reusable Codex working agreement.
