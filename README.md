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
- Run at most one install task at a time and refresh installed-version state after success.
- Persist known project paths without copying project configuration, runtime state, or task logs into app storage.
- Native SwiftUI sidebar with Overview, Projects and Plugins screens.
- Unit tests for process streaming/cancellation, asdf/plugin output, installed versions, `.tool-versions`, install planning, availability decisions, project snapshots and preferences.
- macOS GitHub Actions CI running `swift test`.

## Development

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before making architectural changes or using Codex for follow-up development. It contains the roadmap, architecture boundaries, persistence decisions, project availability/install semantics, safety rules for CLI/file mutations and a reusable Codex prompt.
