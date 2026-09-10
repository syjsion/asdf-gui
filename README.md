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

The installer never edits shell startup files automatically. After asdf is ready, **Shell Integration** (`⌘⇧S`) can configure Terminal use explicitly. It supports Zsh (`~/.zshrc`) and Bash (`~/.bash_profile`), previews the exact managed block first, and only writes after confirmation. The block adds the active asdf executable directory plus `${ASDF_DATA_DIR:-$HOME/.asdf}/shims` to `PATH`.

Fresh installations with no plugins or projects also get a one-time **Getting Started** window. It links directly to Shell Integration and Plugin Manager, then points users to Versions and Projects in the main sidebar.

## Language

asdf GUI supports **English and Simplified Chinese (简体中文)**. The initial default follows the macOS preferred language, and the language can be changed at any time from **Settings → Language** without restarting the app. Packaged `.app`/DMG builds include the Chinese localization resources.

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

## Current features

- English / Simplified Chinese UI with an in-app language switch.
- Detect asdf in common installation locations and allow a persisted custom executable path.
- Dedicated missing-asdf setup experience with verified one-click installation from official GitHub release assets.
- Explicit Zsh/Bash Shell Integration with preview, managed markers, update/remove support, and configuration-race protection.
- One-time Getting Started guide for fresh installations, reopenable from the app menu.
- Overview of asdf version, executable, plugins, and managed projects.
- Card-based Projects page that keeps project headers, paths, tool requirements, fallback states, and actions visually separated.
- Add/remove managed project folders and read `.tool-versions` without duplicating configuration into app storage.
- Preserve comments and ordered fallback chains when interpreting `.tool-versions`.
- Compare project requirements with installed asdf runtimes and show Installed, Missing, System, Local path, Plugin missing, or Unknown state.
- Install missing project runtimes with live stdout/stderr, cancellation, deterministic fallback planning, and post-success refresh.
- Browse installed/latest/available versions per plugin with search and Installed-only filtering.
- **Installed runtime versions are always listed before the full available catalog.**
- Install or uninstall individual runtime versions; uninstall always requires confirmation and shows managed-project usage impact.
- Set a project version through `asdf set` or a Home default through `asdf set -u`, with explicit configuration-impact confirmation.
- **Plugin Manager** window (`⌘⇧P`) for Add, Update, Update All, and Remove.
- **Diagnostics** window (`⌘⇧D`) for `asdf info`, `asdf where`, `asdf which`, and `asdf reshim`.
- Native **Set Runtime Version** window (`⌘⇧V`).
- **About asdf GUI** window with app/build/asdf information and GitHub Release update checking.
- Update checking includes prereleases (required by the current ad-hoc release channel), compares semantic versions, and selects the correct arm64/x86_64 DMG when available.
- Streaming/cancellable `Foundation.Process` command runner with no shell-string interpolation.
- Reproducible `.app` and DMG packaging directly from SwiftPM, including localization resources.
- No-account ad-hoc GitHub prerelease workflow plus optional Developer ID/notarization mode later.
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

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before making architectural changes or using Codex for follow-up development. It documents architecture boundaries, command contracts, destructive-action policies, project/version/plugin semantics, localization, update checking, bootstrap/shell-integration policy, release modes, roadmap status, and the Codex working agreement.
