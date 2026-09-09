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
- Read and visualize each project's `.tool-versions`, including fallback version chains.
- Persist known project paths without copying project configuration into app storage.
- Native SwiftUI sidebar with Overview, Projects and Plugins screens.
- Unit tests for asdf/plugin parsing, `.tool-versions` parsing and preferences.
- macOS GitHub Actions CI running `swift test`.

## Development

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before making architectural changes or using Codex for follow-up development. It contains the roadmap, architecture boundaries, persistence decisions, safety rules for CLI/file mutations and a reusable Codex prompt.
