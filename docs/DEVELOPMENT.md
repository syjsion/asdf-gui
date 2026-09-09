# Development Guide

This document is the handoff/reference for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf itself. The CLI and `.tool-versions` files remain the sources of truth; the app is a typed UI/service layer over them.

## Technical constraints

- macOS only for now.
- Swift + SwiftUI + Foundation. Avoid React, Electron, Tauri and WebView.
- Prefer Apple frameworks and keep third-party dependencies at zero unless a dependency clearly reduces maintenance risk.
- Keep CLI parsing out of SwiftUI views.
- Never build normal asdf commands through `/bin/zsh -c` when `Process.executableURL` + `arguments` can express the operation safely.
- Destructive operations must show impact and require explicit user confirmation.
- Only one long-running/write asdf operation may run application-wide at a time.
- MVP assumes non-App-Sandbox distribution (Developer ID + notarized DMG later).
- Project configuration is read from disk when displayed/refreshed. Do not duplicate `.tool-versions` contents into persistent app state.
- Version-browser results are ephemeral. Do not persist large `list all` results.

## Architecture

```text
SwiftUI Views
  -> AppModel / feature state + task orchestration
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

- `AppModel`: UI-facing state and orchestration. Keep it `@MainActor`. It joins project requirements with current asdf state, owns transient version-browser state, and owns the currently active project-install or general version-operation task. It must not parse command output itself.
- `AsdfService`: typed asdf operations and output parsing, including installed/available/latest queries, runtime installation and runtime uninstallation.
- `AsdfCommandRunner`: process execution, stdout/stderr draining, output streaming, result collection and cancellation only. It should not know product/asdf concepts.
- `ProjectService`: reads project-local configuration and produces snapshots for the UI. It must not mutate `.tool-versions` unless a future explicit mutation API is added.
- `ToolVersionsParser`: deterministic parser for `.tool-versions`; preserve version/fallback order.
- `RequirementStatusResolver`: pure mapping from a required version + plugin/installed state to UI-neutral availability state.
- `ProjectInstallPlanner`: pure decision layer that chooses which missing runtime should be installed for each unsatisfied project requirement.
- `VersionCatalog`: pure merge/deduplication layer for available, installed and latest versions used by the Versions UI.
- `VersionUsageInspector`: pure project-impact lookup used before uninstalling an installed version.
- `PreferencesStore`: lightweight app preferences only (selected asdf path and known project paths for now).
- Views: rendering and user interaction. No command construction or command-output parsing.

## Command runner contract

`AsdfCommandRunner.run` is the only normal process-execution primitive for asdf commands.

It provides:

- Direct executable + argument invocation; no shell-string interpolation.
- Concurrent draining of stdout and stderr while the process is running, avoiding Pipe-buffer deadlocks on verbose installs/builds.
- An optional `onOutput` callback that receives `AsdfOutputEvent` chunks as they arrive.
- A complete `AsdfCommandResult` containing stdout, stderr and exit code after termination.
- Swift task cancellation: cancelling the task terminates the underlying `Process` and the async call resolves with `CancellationError`.

Important for future UI/task work:

- `onOutput` is invoked from process/file-handle callbacks and is not main-actor isolated. UI state updates must hop to `MainActor`.
- Output events are chunks, not guaranteed complete lines. Do not build parsers that assume one callback equals one line.
- Typed parsers should continue using the complete `AsdfCommandResult` unless real-time parsing is specifically required.
- Long-running operations should be owned by a cancellable Swift `Task`; do not create a second process-cancellation mechanism in the View layer.
- Project installs and general version install/uninstall operations share one global mutual-exclusion policy. Do not allow two asdf write tasks to run concurrently without a deliberate, documented redesign.

## Project install workflow

`Install Missing` is the project-centric runtime-install workflow. Its behavior is intentionally conservative and deterministic.

Planning rules:

1. Read the project's current `.tool-versions`; do not rewrite it.
2. For each tool requirement, preserve the configured fallback order.
3. If any fallback is already satisfied (`Installed`, `System`, or `Local path`), plan no installation for that tool.
4. If the requirement is fully unsatisfied, choose the first fallback whose current state is `Missing`.
5. `Plugin missing` and `Unknown` are blocking states and are never silently converted into install operations.
6. A tool is planned at most once, even if malformed/repeated configuration lines exist.

Execution rules:

- Execute each planned item as `asdf install <tool> <version>` with the project directory as `Process.currentDirectoryURL`.
- Run planned items sequentially so output and failure ownership are clear.
- Surface stdout and stderr live in the Projects task panel.
- Task logs are in-memory only and capped at 200,000 characters; older output is truncated.
- Cancelling the Swift task propagates to `AsdfCommandRunner`, which terminates the current process. No later planned items start after cancellation.
- Stop the plan on the first failed install and keep its error/log visible.
- After a fully successful plan, refresh installed-version state so the project UI immediately reflects the new runtime availability.
- Completed/failed/cancelled tasks remain visible until explicitly dismissed.

Do not broaden this workflow to auto-install missing plugins. Plugin installation is a separate explicit action with its own UX and policy.

## Versions browser and general version-management contract

The Versions screen is lazy: data is loaded only for the selected installed plugin.

Read commands:

- `asdf list <tool>` -> installed versions.
- `asdf latest <tool>` -> latest stable version reported by the plugin.
- `asdf list all <tool>` -> available versions.

Read rules:

- Do not eagerly run `asdf list all` for every installed plugin at app launch. Some plugins return large lists or perform relatively expensive work.
- Load version data only when the user selects a plugin or explicitly refreshes it.
- Switching plugins is driven by a cancellable SwiftUI `.task(id:)`. Old requests must not overwrite the newly selected plugin's state.
- Installed/latest/available queries are allowed to fail independently. Preserve successful partial results and surface per-query errors.
- Results are transient and are not persisted to `UserDefaults`.
- `VersionCatalog` merges available + installed + latest with stable order and deduplication. This preserves old installed versions that are no longer in `list all` and preserves a latest value even if it is missing from the available list.
- Search and the All/Installed filter are UI-only operations and do not execute additional asdf commands.

Write commands:

- Install: `asdf install <tool> <version>`.
- Uninstall: `asdf uninstall <tool> <version>`.

Write rules:

- A non-installed version may be explicitly installed from the Versions table.
- An installed version may be uninstalled only after an explicit destructive confirmation.
- Before presenting uninstall confirmation, `VersionUsageInspector` scans the current in-memory `ProjectSnapshot` list (which is sourced from project `.tool-versions` files) and returns every managed project that explicitly references the exact `<tool>, <version>` pair.
- Fallback references still count as usage. If a project lists `python 3.13.2 3.12.9 system`, uninstalling `3.12.9` must show that project in the impact list.
- Usage matching is exact. Do not treat prefixes as references.
- The confirmation must remain available even when zero projects reference the version; uninstall is always destructive.
- When projects reference a version, the UI should explain that uninstalling may leave those projects missing a runtime unless another configured fallback remains usable.
- Version install/uninstall uses the same streaming/cancellable command runner as project installs.
- Only one long-running/write operation may run application-wide. A Versions operation blocks Project `Install Missing`, and vice versa.
- On successful install/uninstall, refresh project installed-version state and refresh the selected tool's installed-version list so UI status changes immediately.
- Do not modify `.tool-versions` as a side effect of version install/uninstall.

## Persistence decisions

The current build is intentionally non-sandboxed, so known projects are persisted as standardized absolute paths in `UserDefaults`.

Persisted values:

- Optional custom asdf executable path.
- Known project directory paths.

Not persisted:

- `.tool-versions` contents.
- asdf plugin/version state.
- installed/available/latest lookup results.
- command/task output.
- project install task state.
- version operation task state.

If App Sandbox support is introduced later, project access will need security-scoped bookmarks and this section must be updated before changing the persistence format.

## Current implementation

Implemented:

- Swift Package based macOS SwiftUI executable.
- Common-path asdf executable discovery.
- Manual asdf executable selection with executable validation.
- Persisted custom executable preference with reset to auto-detection.
- Streaming, continuously drained, cancellable Foundation `Process` runner.
- `asdf version` status.
- `asdf plugin list --urls` parsing.
- `asdf list <tool>` installed-version lookup and parser.
- `asdf list all <tool>` available-version lookup.
- `asdf latest <tool>` latest-version lookup.
- Typed `asdf install <tool> <version>` operation with streamed output.
- Typed `asdf uninstall <tool> <version>` operation with streamed output.
- Overview, Projects, Versions and Plugins screens.
- Projects add/remove and persisted known project paths.
- Read-only `.tool-versions` parsing, including multiple fallback versions per tool and inline comments.
- Project state for missing folders or missing `.tool-versions` files.
- Per-version project availability: Installed, Missing, System, Local path, Plugin missing, or Unknown.
- Fallback-aware requirement readiness.
- `Install Missing` planning, sequential install task, live log, cancellation and post-success refresh.
- Lazy Versions browser with plugin selection, Installed/Latest/Available summary, All/Installed scope, search, partial-error display and version catalog deduplication.
- Per-version Install and Uninstall actions in Versions.
- Explicit uninstall confirmation with managed-project usage impact list.
- General version operation task panel with live stdout/stderr, cancellation, failure retention and log truncation.
- Global mutual exclusion between project install tasks and general version operations.
- Parser, availability-resolution, install-planning, version-catalog, version-usage, project snapshot, persistence, command streaming and command cancellation tests.
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
- [x] Process cancellation and streaming output.

### Phase 2 — Projects

- [x] Add/remove known project folders.
- [x] Parse `.tool-versions` without mutating it.
- [x] Show required vs installed versions.
- [x] `Install missing versions` action with task log/cancel UI.
- [x] Persist project list.

### Phase 3 — Version management

- [x] Installed-version query API: `asdf list <tool>`.
- [x] Dedicated installed/available versions browser.
- [x] Available versions: `asdf list all <tool>`.
- [x] Latest version lookup.
- [x] General install/uninstall with task log.
- [ ] Set project/home versions through `asdf set`.
- [x] Show known projects using a version before uninstall.

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

## asdf command/reference assumptions

Keep these behaviors aligned with current official asdf documentation before changing related code:

- `.tool-versions` may list multiple versions for a tool, separated by spaces; order is meaningful as a fallback chain.
- `.tool-versions` supports full-line and inline comments.
- Version entries may include exact versions, `ref:*`, `path:*`, and `system`.
- `asdf list <tool>` lists installed versions; modern asdf exits successfully when no versions are installed.
- `asdf list all <tool>` lists versions available from the plugin.
- `asdf latest <tool>` returns the latest stable version reported by the plugin.
- `asdf install <tool> <version>` installs a specific runtime version for an installed plugin.
- `asdf uninstall <tool> <version>` uninstalls a specific installed runtime version. For `ref:*` installs, use the same reference string when uninstalling.
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
5. Keep availability, install-planning, version-catalog and usage-impact decisions in pure non-UI logic so they can be unit tested.
6. Long-running operations must use the existing streaming/cancellable command runner; do not add another Process wrapper.
7. Preserve the single-active-write-operation rule unless a deliberate concurrency design is documented and tested.
8. Destructive runtime/plugin removal must remain explicitly confirmed and surface known impact before execution.
9. Do not auto-install plugins as a side effect of runtime installation.
10. Do not eagerly query all available versions for every plugin; the Versions screen must remain lazy.
11. Add or update tests for parsers and non-UI logic.
12. Do not introduce shell-string command execution for normal asdf commands.
13. Do not silently change `.tool-versions`; mutations need explicit UI intent.
14. Update this document when architecture, commands, persistence, distribution, task policy, version-management policy or roadmap status changes.
15. Run `swift test` and report failures before considering a change complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first and follow its architecture/constraints.
Implement <task> in small focused changes. Keep CLI construction in AsdfService,
process execution in AsdfCommandRunner, project file access in ProjectService,
and UI logic in SwiftUI views/models. Reuse the existing streaming/cancellable
runner and preserve the documented single-write-operation and destructive-action
policies. Keep status/planning/catalog/impact decisions in pure testable logic.
Add tests for parsing and non-UI behavior. Run swift test. Update DEVELOPMENT.md
if this changes architecture, supported asdf commands, persistence, task policy,
version-management policy, or roadmap status.
```

## Design principles

- The app should explain state, not merely expose CLI buttons.
- Prefer project-centric workflows over command-centric workflows.
- Preserve asdf and `.tool-versions` as sources of truth.
- Make failure output visible and actionable.
- Avoid hiding potentially expensive/destructive behavior.
- Show the impact of destructive actions before executing them.
