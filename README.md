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

asdf GUI supports **English and Simplified Chinese (简体中文)**. The initial default follows the macOS preferred language, and the language can be changed at any time from **Settings → Language** without restarting the app.

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
- Card-based Projects page with **search by project/path/tool** and sorting by **name, path, or tool count**.
- Add/remove managed project folders and reread `.tool-versions` from disk instead of caching project configuration.
- **Visual `.tool-versions` management per project:** add a tool, edit its version/fallback chain, reorder fallbacks, and remove a tool without exposing a raw text editor.
- Add/edit/reorder writes run `asdf set <tool> <version...>` in the selected project directory.
- Because asdf 0.20 has no command that deletes one tool entry, removal is the single guarded direct-file exception with race/duplicate/content/permission protection.
- Compare project requirements with installed asdf runtimes and show Installed, Missing, System, Local path, Plugin missing, or Unknown state.
- Install missing project runtimes with live stdout/stderr, cancellation, deterministic fallback planning, and post-success refresh.
- Browse installed/latest/available versions per plugin with search and Installed-only filtering; installed versions stay first.
- Install or uninstall individual runtime versions with managed-project usage impact before uninstall.
- Set project versions through `asdf set` or a Home default through `asdf set -u`.
- **Resolution** sidebar for directory-aware `asdf current` results: effective version, source `.tool-versions`, and installed state for Home or a managed project.
- **Shim & Command Explorer** for `asdf shimversions <command>` plus directory-aware `asdf which <command>` so commands like `node`, `npm`, `python`, or `yarn` can be explained visually.
- **Plugin Manager** (`⌘⇧P`) for Add / Update / Update All / Remove plus **Discover Plugins**, a searchable `asdf plugin list all` catalog that installs with the returned Git URL when available.
- **Diagnostics** (`⌘⇧D`) for `asdf info`, `asdf where`, `asdf which`, and `asdf reshim`.
- Native **Set Runtime Version** window (`⌘⇧V`).
- **About asdf GUI** window with app/build/asdf information and GitHub Release update checking, including prereleases and architecture-specific DMGs.
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

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before making architectural changes or using Codex for follow-up development. It documents architecture boundaries, command contracts, `.tool-versions` mutation rules, resolution/shim parsing, plugin discovery, destructive-action policies, localization, update checking, bootstrap/shell-integration policy, release modes, roadmap status, and the Codex working agreement.
