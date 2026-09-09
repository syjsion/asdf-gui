# Development Guide

This document is the handoff/reference for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf itself. The asdf CLI and `.tool-versions` files remain the sources of truth; the app is a typed UI/service layer over them.

## Technical constraints

- macOS only for now.
- Swift + SwiftUI + Foundation. Avoid React, Electron, Tauri and WebView.
- Prefer Apple frameworks and keep third-party dependencies at zero unless a dependency clearly reduces maintenance risk.
- Keep CLI parsing and command construction out of SwiftUI views.
- Never build normal asdf commands through `/bin/zsh -c` when `Process.executableURL` + `arguments` can express the operation safely.
- Destructive operations must show impact and require explicit user confirmation.
- Only one long-running asdf write operation may run application-wide at a time.
- Short configuration writes (`asdf set`) must refuse to start while a long-running write operation is active.
- MVP assumes non-App-Sandbox distribution (Developer ID + notarized DMG later).
- Project configuration is read from disk when displayed/refreshed. Do not persist copies of `.tool-versions` contents.
- Version-browser results are ephemeral. Do not persist large `list all` results.

## Architecture

```text
SwiftUI Views / feature windows
  -> AppModel + AppModel feature extensions
      -> AsdfService
          -> AsdfCommandRunner
              -> Foundation.Process + Pipe
      -> ProjectService
          -> ToolVersionsParser
          -> RequirementStatusResolver
          -> ProjectInstallPlanner
          -> FileManager
      -> VersionCatalog
      -> VersionUsageInspector
      -> PreferencesStore
          -> UserDefaults
```

### Responsibilities

- `AppModel`: UI-facing state and orchestration. Keep it `@MainActor`. It joins project requirements with current asdf state and owns long-running task state.
- `AppModel+VersionSelection`: orchestration for short project/Home `asdf set` writes. It may instantiate `AsdfService`, but must not construct CLI strings itself.
- `AsdfService`: typed asdf operations and output parsing, including version queries, install/uninstall, and `asdf set`.
- `AsdfCommandRunner`: process execution, stdout/stderr draining, output streaming, result collection and cancellation only. It must not know product/asdf concepts.
- `ProjectService`: reads project-local configuration and produces snapshots for the UI. Direct file mutation remains disallowed; configuration changes go through typed `asdf set` operations.
- `ToolVersionsParser`: deterministic parser for `.tool-versions`; preserve version/fallback order.
- `RequirementStatusResolver`: pure mapping from required version + plugin/installed state to UI-neutral availability state.
- `ProjectInstallPlanner`: pure decision layer for project `Install Missing`.
- `VersionCatalog`: pure merge/deduplication layer for available, installed and latest versions.
- `VersionUsageInspector`: pure project-impact lookup used before uninstalling a version.
- `PreferencesStore`: lightweight preferences only (custom asdf path and known project paths for now).
- Views: rendering and user interaction. No command construction or output parsing.

## Command runner contract

`AsdfCommandRunner.run` is the only normal process-execution primitive for asdf commands.

It provides:

- Direct executable + argument invocation; no shell-string interpolation.
- Concurrent draining of stdout and stderr while a process runs.
- Optional `AsdfOutputEvent` streaming callbacks.
- A complete `AsdfCommandResult` with stdout, stderr and exit code.
- Swift Task cancellation that terminates the underlying `Process` and resolves with `CancellationError`.

Rules:

- `onOutput` is not main-actor isolated; UI updates must hop to `MainActor`.
- Output callbacks are chunks, not guaranteed complete lines.
- Typed parsers should use complete command results unless real-time parsing is specifically required.
- Long-running operations must use this runner; do not add another Process wrapper.
- Project installs and general version install/uninstall share one global mutual-exclusion policy.

## Project install workflow

`Install Missing` is conservative and deterministic.

Planning:

1. Read the current project `.tool-versions`; do not rewrite it.
2. Preserve each tool's configured fallback order.
3. If any fallback is already satisfied (`Installed`, `System`, or `Local path`), install nothing for that tool.
4. Otherwise choose the first fallback currently classified as `Missing`.
5. `Plugin missing` and `Unknown` block automatic installation.
6. Plan each tool at most once.

Execution:

- Run `asdf install <tool> <version>` with the project directory as `Process.currentDirectoryURL`.
- Execute planned items sequentially.
- Stream stdout/stderr into the Projects task panel.
- Cap in-memory logs at 200,000 characters.
- Cancellation terminates the current process and prevents later planned items from starting.
- Stop on the first failed install and keep diagnostics visible.
- Refresh installed-version state after full success.

Do not auto-install missing plugins as a side effect.

## Versions browser and general version management

The Versions screen is lazy: query only the selected installed plugin.

Read commands:

- `asdf list <tool>` -> installed versions.
- `asdf latest <tool>` -> latest stable version reported by the plugin.
- `asdf list all <tool>` -> available versions.

Read rules:

- Never eagerly run `asdf list all` for every plugin at launch.
- Plugin switching uses cancellable `.task(id:)`; old responses must not overwrite a new selection.
- Installed/latest/available queries may fail independently; preserve successful partial results.
- Results are transient and not persisted.
- `VersionCatalog` merges available + installed + latest with stable order and deduplication.
- Search and All/Installed filters are UI-only.

Write commands:

- Install: `asdf install <tool> <version>`.
- Uninstall: `asdf uninstall <tool> <version>`.

Write rules:

- Available versions may be explicitly installed.
- Installed versions may be uninstalled only after destructive confirmation.
- `VersionUsageInspector` must show all managed projects that exactly reference the selected `<tool>, <version>` pair before uninstall.
- Fallback references count as usage; prefix matches do not.
- Confirmation is required even when zero managed projects reference the version.
- Version install/uninstall uses the same streaming/cancellable runner as project installs.
- Only one long-running write operation may run application-wide.
- Refresh project installed-version state and the selected tool after successful install/uninstall.
- Do not modify `.tool-versions` as a side effect of version install/uninstall.

## Version selection (`asdf set`) contract

Version selection is exposed in a dedicated native window opened via **Set Runtime Version…** (`⌘⇧V`). It is intentionally separate from install/uninstall task UI because `asdf set` is a short configuration write, not a long-running build/download task.

Typed commands:

- Project: `asdf set <tool> <version...>` with `Process.currentDirectoryURL` set to the selected managed project directory.
- Home: `asdf set -u <tool> <version...>` with no project working directory requirement.

Current UI behavior:

- Scope is either Project or Home.
- Tool choices come from installed plugins.
- Version choices are installed versions plus the special `system` value.
- The UI writes an exact selected version, never the moving `latest` token.
- Project mode shows the current local project version/fallback chain for the selected tool before applying.
- Project mode requires explicit confirmation and explains that selecting one version replaces the tool's existing fallback chain with that single version.
- Home mode requires explicit confirmation and explains that `$HOME/.tool-versions` is updated while project-local settings still override it.
- Project selection uses only managed projects already stored by the app.
- `asdf set` is invoked through `AsdfService`; Views never edit `.tool-versions` directly.
- A short `asdf set` write must refuse to start if a long-running install/uninstall operation is active.
- After a successful project write, refresh project snapshots and installed-version availability so the UI reflects the new local configuration immediately.
- Home writes currently report success but do not maintain a separate cached Home configuration model.

Future improvements may add ordered multi-version/fallback editing. If that is added, preserve order and test the exact `asdf set <tool> <version...>` argument sequence.

## Persistence decisions

The build is intentionally non-sandboxed, so known projects are persisted as standardized absolute paths in `UserDefaults`.

Persisted:

- Optional custom asdf executable path.
- Known project directory paths.

Not persisted:

- `.tool-versions` contents.
- asdf plugin/version state.
- installed/available/latest lookup results.
- command/task output.
- project install task state.
- general version operation task state.
- version-selection form state.

If App Sandbox support is introduced later, project access must migrate to security-scoped bookmarks and this section must be updated first.

## Current implementation

Implemented:

- Swift Package macOS SwiftUI executable.
- Common-path asdf discovery and custom executable preference.
- Streaming/cancellable Foundation `Process` runner.
- `asdf version`, `plugin list --urls`, `list`, `list all`, `latest`.
- Typed runtime install and uninstall.
- Typed project/Home `asdf set`.
- Overview, Projects, Versions and Plugins screens.
- Dedicated Set Runtime Version window and app command (`⌘⇧V`).
- Managed project persistence and read-only `.tool-versions` parsing.
- Project required-vs-installed status and fallback-aware readiness.
- Project `Install Missing` with live logs/cancel.
- Lazy version browser with search/filter.
- Per-version install/uninstall with live logs/cancel.
- Uninstall managed-project impact confirmation.
- Project/Home exact-version selection including `system`.
- Tests for parsers, project availability/planning, version catalog/usage, persistence, process streaming/cancellation, and `asdf set` argument/working-directory behavior.
- macOS GitHub Actions CI running `swift test`.

Run locally:

```bash
swift test
swift run asdf-gui
```

Xcode can open `Package.swift` directly.

## Roadmap

### Phase 1 — Foundation

- [x] Native SwiftUI shell/navigation.
- [x] Process runner and typed service boundary.
- [x] asdf detection/version/plugin list.
- [x] Parsing tests.
- [x] Manual executable picker + persistence.
- [x] Process cancellation and streaming output.

### Phase 2 — Projects

- [x] Add/remove known project folders.
- [x] Parse `.tool-versions` without direct mutation.
- [x] Show required vs installed versions.
- [x] `Install Missing` with task log/cancel.
- [x] Persist project list.

### Phase 3 — Version management

- [x] Installed-version query (`asdf list`).
- [x] Installed/available version browser.
- [x] Available versions (`asdf list all`).
- [x] Latest lookup.
- [x] General install/uninstall with task log.
- [x] Set project/Home versions through `asdf set` / `asdf set -u`.
- [x] Show managed projects using a version before uninstall.

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

Project availability is derived and non-persisted:

1. `ProjectService` reads `.tool-versions` and preserves each tool's ordered fallback chain.
2. `AsdfService` lists installed versions for installed plugins.
3. `RequirementStatusResolver` maps each token to a neutral status.
4. `AppModel` considers a requirement satisfied when any configured fallback is usable.

Token handling:

- Exact versions and `ref:*`: compare against `asdf list <tool>` output.
- `system`: satisfied when the plugin is installed; no asdf-managed runtime install required.
- `path:*`: treated as a local-path requirement when the plugin is installed; path existence is not yet validated.
- Missing plugin: reported before version availability.
- Lookup failure: status is `Unknown` and the command error is shown.

## asdf command/reference assumptions

Verify current upstream docs before changing code that depends on these behaviors.

- `.tool-versions` may list multiple ordered versions/fallbacks for a tool.
- `.tool-versions` supports full-line and inline comments.
- Version entries may include exact versions, `ref:*`, `path:*`, and `system`.
- `asdf list <tool>` lists installed versions.
- `asdf list all <tool>` lists plugin-available versions.
- `asdf latest <tool>` returns the plugin's latest stable version.
- `asdf install <tool> <version>` installs a runtime.
- `asdf uninstall <tool> <version>` uninstalls a runtime; `ref:*` uninstall uses the same reference string.
- `asdf set <tool> <version...>` writes/creates the current directory's `.tool-versions` entry.
- `asdf set -u <tool> <version...>` writes/creates the Home `.tool-versions` entry.
- `asdf set -p` targets the closest parent `.tool-versions`; it is not exposed by the current UI.
- Project-local `.tool-versions` entries override Home defaults during version resolution.
- The GUI should prefer exact versions over storing a moving `latest` token.

## Codex working agreement

When asking Codex to modify this repository:

1. Read `docs/DEVELOPMENT.md` before editing.
2. Preserve the SwiftUI/Foundation-only architecture unless explicitly changing it.
3. Keep asdf CLI calls behind `AsdfService` and process handling behind `AsdfCommandRunner`.
4. Keep direct project file reads/writes behind project/file services; configuration mutation should normally use typed `asdf set`.
5. Keep availability, planning, catalog and impact decisions in pure testable logic where practical.
6. Long-running operations must use the existing streaming/cancellable runner.
7. Preserve the single-active-long-write rule unless a deliberate concurrency design is documented/tested.
8. Short `asdf set` writes must not start while a long-running write is active.
9. Destructive runtime/plugin removal must be explicitly confirmed and surface known impact.
10. Do not auto-install plugins as a side effect of runtime installation.
11. Keep Versions lazy; do not eagerly query all available versions for every plugin.
12. Add/update tests for parser, command, policy and non-UI logic changes.
13. Do not introduce shell-string execution for normal asdf commands.
14. Do not silently mutate `.tool-versions`; every configuration write needs explicit UI intent and impact wording.
15. Update this document when architecture, supported commands, persistence, task policy, version-management policy or roadmap status changes.
16. Run `swift test` and report failures before considering a change complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first and follow its architecture/constraints.
Implement <task> in focused changes. Keep CLI semantics in AsdfService,
process execution in AsdfCommandRunner, project/file access behind services,
and UI interaction in SwiftUI views/models. Preserve the documented write,
destructive-action, and version-selection policies. Add tests for command/non-UI
behavior. Run swift test. Update DEVELOPMENT.md when architecture, commands,
persistence, task policy, or version-management behavior changes.
```

## Design principles

- Explain state; do not merely expose CLI buttons.
- Prefer project-centric workflows over command-centric workflows.
- Preserve asdf and `.tool-versions` as sources of truth.
- Make failure output visible and actionable.
- Avoid hiding expensive or destructive behavior.
- Show configuration/destructive impact before executing it.
