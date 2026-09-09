# asdf GUI

Native macOS GUI for [asdf](https://asdf-vm.com/), built with SwiftUI and Foundation.

The project intentionally keeps asdf and `.tool-versions` as the sources of truth. The app provides a typed, visual layer over the existing CLI rather than reimplementing version management.

## Requirements

- macOS 14+
- Xcode 15.3+ or a compatible Swift 5.10 toolchain
- asdf installed locally

## Run

```bash
swift test
swift run asdf-gui
```

You can also open `Package.swift` in Xcode and run the `asdf-gui` executable target.

## Current features

- Detect asdf in common installation locations.
- Choose and persist a custom asdf executable, or reset to automatic detection.
- Show asdf version and active executable path.
- List installed plugins and repository URLs.
- Add/remove known project folders.
- Read each project's `.tool-versions`, including comments and fallback version chains.
- Compare project requirements with `asdf list <tool>` and show Installed, Missing, System, Local path, Plugin missing, or Unknown state.
- Install the first missing runtime for each fully unsatisfied project requirement with a live stdout/stderr log and cancellation.
- Browse versions per installed plugin with `asdf list`, `asdf latest`, and `asdf list all`.
- Search the version catalog and switch between all versions and installed-only results.
- Install an individual available version from the Versions screen with a live cancellable task log.
- Uninstall an installed version only after an explicit destructive confirmation.
- Before uninstalling, show every managed project whose `.tool-versions` explicitly references that tool/version.
- Keep project install tasks and general version operations mutually exclusive so only one asdf write task runs at a time.
- Refresh project/runtime availability immediately after successful install or uninstall operations.
- Persist known project paths without copying project configuration, runtime state, version-browser results, or task logs into app storage.
- Native SwiftUI sidebar with Overview, Projects, Versions and Plugins screens.
- Unit tests for process streaming/cancellation, asdf/plugin output, version catalog merging, project usage checks, `.tool-versions`, install planning, availability decisions, project snapshots and preferences.
- macOS GitHub Actions CI running `swift test`.

## Development

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before making architectural changes or using Codex for follow-up development. It contains the roadmap, architecture boundaries, persistence decisions, project availability/install semantics, version-management safety rules, command assumptions and a reusable Codex prompt.
