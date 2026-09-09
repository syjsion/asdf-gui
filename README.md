# asdf GUI

Native macOS GUI for [asdf](https://asdf-vm.com/), built with SwiftUI and Foundation.

The project keeps asdf and `.tool-versions` as the sources of truth. The app is a typed, visual control layer over the existing CLI rather than a reimplementation of version management.

## Requirements

- macOS 14+
- Xcode 15.3+ or a compatible Swift 5.10 toolchain
- asdf installed locally

## Run

```bash
swift test
swift run asdf-gui
```

You can also open `Package.swift` directly in Xcode.

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
- macOS GitHub Actions CI running the full `swift test` suite.

## Development

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before making architectural changes or using Codex for follow-up development. It documents architecture boundaries, command contracts, destructive-action policies, project/version/plugin semantics, diagnostics behavior, roadmap status, and a reusable Codex working agreement.
