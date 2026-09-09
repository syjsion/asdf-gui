# Development Guide

This document is the handoff/reference for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf itself. The CLI remains the source of truth; the app is a typed UI/service layer over it.

## Technical constraints

- macOS only for now.
- Swift + SwiftUI + Foundation. Avoid React, Electron, Tauri and WebView.
- Prefer Apple frameworks and keep third-party dependencies at zero unless a dependency clearly reduces maintenance risk.
- Keep CLI parsing out of SwiftUI views.
- Never build commands through `/bin/zsh -c` when `Process.executableURL` + `arguments` can express the operation safely.
- Destructive operations must show impact and require explicit user confirmation.
- MVP assumes non-App-Sandbox distribution (Developer ID + notarized DMG later).

## Architecture

```text
SwiftUI Views
  -> AppModel / feature state
      -> AsdfService
          -> AsdfCommandRunner
              -> Foundation.Process

Project features (next phase)
  -> ProjectService
      -> FileManager
      -> .tool-versions parser
```

### Responsibilities

- `AppModel`: UI-facing state and orchestration. Keep it `@MainActor`.
- `AsdfService`: typed asdf operations and output parsing.
- `AsdfCommandRunner`: process execution only. It should not know product concepts.
- Views: rendering and user interaction. No command construction or output parsing.

## Current MVP

Implemented:

- Swift Package based macOS SwiftUI executable.
- Common-path asdf executable discovery.
- `asdf version` status.
- `asdf plugin list --urls` parsing.
- Overview and Plugins screens.
- Settings placeholder showing detected executable.
- Unit tests for plugin parsing.

Run locally:

```bash
swift test
swift run asdf-gui
```

Xcode can open `Package.swift` directly.

## Roadmap

### Phase 1 — Foundation (current PR)

- [x] Native SwiftUI shell and navigation.
- [x] Process runner and typed service boundary.
- [x] asdf detection/version/plugin list.
- [x] Basic parsing tests.
- [ ] Manual executable picker + persisted preference.
- [ ] Better process cancellation and streaming output.

### Phase 2 — Projects

- [ ] Add/remove known project folders.
- [ ] Parse `.tool-versions` without mutating it.
- [ ] Show required vs installed versions.
- [ ] `Install missing versions` action.
- [ ] Persist project bookmarks/list.

### Phase 3 — Version management

- [ ] Installed versions: `asdf list <tool>`.
- [ ] Available versions: `asdf list all <tool>`.
- [ ] Latest version lookup.
- [ ] Install/uninstall with task log.
- [ ] Set project/home versions through `asdf set`.
- [ ] Show known projects using a version before uninstall.

### Phase 4 — Plugins and diagnostics

- [ ] Add/update/remove plugins.
- [ ] Destructive plugin-removal confirmation.
- [ ] `where`, `which`, `reshim`, `info` diagnostics.
- [ ] Copyable diagnostic report.

### Phase 5 — Distribution

- [ ] Add an Xcode app project if needed for signing/distribution.
- [ ] Developer ID signing and notarization.
- [ ] DMG packaging.
- [ ] GitHub Actions build/test workflow.

## Codex working agreement

When asking Codex to modify this repository, include these rules in the prompt:

1. Read `docs/DEVELOPMENT.md` before editing.
2. Preserve the SwiftUI/Foundation-only architecture unless the task explicitly changes it.
3. Keep asdf CLI calls behind `AsdfService` and process handling behind `AsdfCommandRunner`.
4. Add or update tests for parsers and non-UI logic.
5. Do not introduce shell-string command execution for normal asdf commands.
6. Do not silently change `.tool-versions`; mutations need explicit UI intent.
7. Update this document when architecture, commands, persistence, distribution, or roadmap status changes.
8. Run `swift test` and report failures before considering a change complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first and follow its architecture/constraints.
Implement <task> in small focused changes. Keep CLI construction in AsdfService,
process execution in AsdfCommandRunner, and UI logic in SwiftUI views/models.
Add tests for parsing/non-UI behavior. Run swift test. Update DEVELOPMENT.md if
this changes architecture, supported asdf commands, persistence, or roadmap status.
```

## Design principles

- The app should explain state, not merely expose CLI buttons.
- Prefer project-centric workflows over command-centric workflows.
- Preserve asdf as source of truth.
- Make failure output visible and actionable.
- Avoid hiding potentially expensive/destructive behavior.
