# Development Guide

This document is the handoff/reference for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf itself. The CLI and `.tool-versions` files remain the source of truth; the app is a typed UI/service layer over them.

## Technical constraints

- macOS only for now.
- Swift + SwiftUI + Foundation. Avoid React, Electron, Tauri and WebView.
- Prefer Apple frameworks and keep third-party dependencies at zero unless a dependency clearly reduces maintenance risk.
- Keep CLI parsing out of SwiftUI views.
- Never build commands through `/bin/zsh -c` when `Process.executableURL` + `arguments` can express the operation safely.
- Destructive operations must show impact and require explicit user confirmation.
- MVP assumes non-App-Sandbox distribution (Developer ID + notarized DMG later).
- Project configuration is read from disk when displayed/refreshed. Do not duplicate `.tool-versions` contents into persistent app state.

## Architecture

```text
SwiftUI Views
  -> AppModel / feature state
      -> AsdfService
          -> AsdfCommandRunner
              -> Foundation.Process
      -> ProjectService
          -> ToolVersionsParser
          -> RequirementStatusResolver
          -> FileManager
      -> PreferencesStore
          -> UserDefaults
```

### Responsibilities

- `AppModel`: UI-facing state and orchestration. Keep it `@MainActor`. It joins project requirements with current asdf state but should not parse command output itself.
- `AsdfService`: typed asdf operations and output parsing, including installed-version queries.
- `AsdfCommandRunner`: process execution only. It should not know product concepts.
- `ProjectService`: reads project-local configuration and produces snapshots for the UI. It must not mutate `.tool-versions` unless a future explicit mutation API is added.
- `ToolVersionsParser`: deterministic parser for `.tool-versions`; preserve version/fallback order.
- `RequirementStatusResolver`: pure mapping from a required version + plugin/installed state to UI-neutral availability state.
- `PreferencesStore`: lightweight app preferences only (selected asdf path and known project paths for now).
- Views: rendering and user interaction. No command construction or output parsing.

## Persistence decisions

The current build is intentionally non-sandboxed, so known projects are persisted as standardized absolute paths in `UserDefaults`.

Persisted values:

- Optional custom asdf executable path.
- Known project directory paths.

Not persisted:

- `.tool-versions` contents.
- asdf plugin/version state.
- installed-version lookup results.
- command output.

If App Sandbox support is introduced later, project access will need security-scoped bookmarks and this section must be updated before changing the persistence format.

## Current implementation

Implemented:

- Swift Package based macOS SwiftUI executable.
- Common-path asdf executable discovery.
- Manual asdf executable selection with executable validation.
- Persisted custom executable preference with reset to auto-detection.
- `asdf version` status.
- `asdf plugin list --urls` parsing.
- `asdf list <tool>` installed-version lookup and parser.
- Overview and Plugins screens.
- Projects screen with add/remove known folders.
- Persisted known project paths.
- Read-only `.tool-versions` parsing, including multiple fallback versions per tool and inline comments.
- Project state for missing folders or missing `.tool-versions` files.
- Per-version availability in Projects: Installed, Missing, System, Local path, Plugin missing, or Unknown.
- Fallback-aware requirement readiness: a requirement is ready when at least one configured fallback is available.
- Parser, availability-resolution, project snapshot, and persistence unit tests.
- macOS GitHub Actions CI running `swift test`.

Run locally:

```bash
swift test
swift run asdf-gui
```

Xcode can open `Package.swift` directly.

## Roadmap

### Phase 1 — Foundation

- [x] Native SwiftUI shell and navigation.
- [x] Process runner and typed service boundary.
- [x] asdf detection/version/plugin list.
- [x] Basic parsing tests.
- [x] Manual executable picker + persisted preference.
- [ ] Better process cancellation and streaming output.

### Phase 2 — Projects

- [x] Add/remove known project folders.
- [x] Parse `.tool-versions` without mutating it.
- [x] Show required vs installed versions.
- [ ] `Install missing versions` action.
- [x] Persist project list.

### Phase 3 — Version management

- [x] Installed-version query API: `asdf list <tool>` (currently surfaced through Projects).
- [ ] Dedicated installed versions browser.
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
- [ ] Release workflow and GitHub Release automation.

## Project availability semantics

Project availability is deliberately a derived, non-persisted view:

1. `ProjectService` reads `.tool-versions` and preserves each tool's ordered fallback chain.
2. `AsdfService` lists installed versions only for plugins that are currently installed.
3. `RequirementStatusResolver` maps each token to a neutral status.
4. `AppModel` considers a tool requirement satisfied if any configured fallback is usable.

Current token handling:

- Exact versions and `ref:*`: compare against `asdf list <tool>` output.
- `system`: treated as satisfied when the plugin is installed; no asdf-managed runtime install is required.
- `path:*`: treated as a local-path requirement when the plugin is installed. The current implementation does not yet validate that the referenced filesystem path exists.
- Missing plugin: reported before version availability because asdf needs the plugin to manage that tool.
- Lookup failure: status is `Unknown` and the command error is shown in the project UI.

Before implementing `Install missing versions`, decide whether fallback chains should install only the first missing exact/ref version or delegate to `asdf install` in the project directory. Document that decision and add tests before exposing the action.

## asdf command/reference assumptions

Keep these behaviors aligned with current official asdf documentation before changing related code:

- `.tool-versions` may list multiple versions for a tool, separated by spaces; order is meaningful as a fallback chain.
- `.tool-versions` supports full-line and inline comments.
- Version entries may include exact versions, `ref:*`, `path:*`, and `system`.
- `asdf list <tool>` lists installed versions; asdf 0.18+ exits successfully when no versions are installed.
- `asdf install` with no tool/version arguments installs the tools defined by the `.tool-versions` file in the command's working directory.
- `asdf set <tool> <version...>` writes project-local configuration; `asdf set -u` writes the home-level configuration.
- `.tool-versions` should contain exact versions (plus supported special values such as `system`, `ref:*`, and `path:*`), not a moving `latest` value.

When implementing commands that mutate configuration or install/uninstall runtimes, verify the current upstream docs first.

## Codex working agreement

When asking Codex to modify this repository, include these rules in the prompt:

1. Read `docs/DEVELOPMENT.md` before editing.
2. Preserve the SwiftUI/Foundation-only architecture unless the task explicitly changes it.
3. Keep asdf CLI calls behind `AsdfService` and process handling behind `AsdfCommandRunner`.
4. Keep project file reads/writes behind `ProjectService` or a dedicated file service.
5. Keep availability/status decisions in pure non-UI logic so they can be unit tested.
6. Add or update tests for parsers and non-UI logic.
7. Do not introduce shell-string command execution for normal asdf commands.
8. Do not silently change `.tool-versions`; mutations need explicit UI intent.
9. Update this document when architecture, commands, persistence, distribution, or roadmap status changes.
10. Run `swift test` and report failures before considering a change complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first and follow its architecture/constraints.
Implement <task> in small focused changes. Keep CLI construction in AsdfService,
process execution in AsdfCommandRunner, project file access in ProjectService,
and UI logic in SwiftUI views/models. Keep status decisions in pure testable logic.
Add tests for parsing/non-UI behavior. Run swift test. Update DEVELOPMENT.md if
this changes architecture, supported asdf commands, persistence, or roadmap status.
```

## Design principles

- The app should explain state, not merely expose CLI buttons.
- Prefer project-centric workflows over command-centric workflows.
- Preserve asdf and `.tool-versions` as sources of truth.
- Make failure output visible and actionable.
- Avoid hiding potentially expensive/destructive behavior.
- Show the impact of destructive actions before executing them.
