# asdf GUI

Native macOS GUI for [asdf](https://asdf-vm.com/), built with SwiftUI and Foundation.

The project intentionally keeps asdf as the source of truth. The app provides a typed, visual layer over the existing CLI rather than reimplementing version management.

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

## Current MVP

- Detect asdf in common installation locations.
- Show asdf version and executable path.
- List installed plugins and repository URLs.
- Native SwiftUI sidebar, overview, plugin list and settings placeholder.
- Parser unit tests.

## Development

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before making architectural changes or using Codex for follow-up development. It contains the roadmap, architecture boundaries, safety rules for CLI/file mutations and a reusable Codex prompt.
