# Development Guide

This is the handoff/reference for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf. The asdf CLI and `.tool-versions` remain the sources of truth; the app is a typed UI/service layer over them.

## Technical constraints

- macOS only for now.
- Swift + SwiftUI + Foundation/AppKit where needed. Do not introduce React, Electron, Tauri, or WebView.
- Prefer Apple frameworks and zero third-party dependencies unless a dependency clearly reduces maintenance risk.
- Keep CLI construction/parsing out of SwiftUI views.
- Run normal asdf commands with `Process.executableURL` + argument arrays; do not construct `/bin/zsh -c` command strings.
- Destructive operations must show known impact and require explicit confirmation.
- Only one asdf write operation may run application-wide at a time.
- The current distribution model is non-App-Sandbox; Developer ID + notarized DMG is the intended release path.
- Do not persist copies of `.tool-versions`, plugin/runtime state, version catalogs, task logs, or diagnostic output.

## Architecture

```text
SwiftUI Views / feature windows
  -> AppModel + feature models
      -> AsdfService
          -> AsdfCommandRunner
              -> Foundation.Process + Pipe
      -> ProjectService
          -> ToolVersionsParser
          -> RequirementStatusResolver
          -> ProjectInstallPlanner
      -> VersionCatalog
      -> VersionUsageInspector
      -> PluginRemovalInspector
      -> DiagnosticReportBuilder
      -> PreferencesStore
          -> UserDefaults
```

### Responsibilities

- `AppModel`: shared UI state, project/runtime state, version-browser state, existing install/version task orchestration, and the application-wide write-operation gate. Keep it `@MainActor`.
- `AppModel+VersionSelection`: short `asdf set` orchestration.
- `PluginManagementModel`: feature-local plugin task state, live logs, cancellation, and removal-impact preparation. It must acquire/release `AppModel`'s external write gate for plugin mutations.
- `DiagnosticsModel`: feature-local diagnostic state. Read diagnostics do not need the write gate; `reshim` must acquire it.
- `AsdfService`: typed asdf operations and output parsing. Views never assemble CLI arguments.
- `AsdfCommandRunner`: process execution, stdout/stderr draining, streaming, result collection, and cancellation only.
- `ProjectService`: reads project configuration from disk; it does not mutate `.tool-versions` directly.
- Pure helpers (`ToolVersionsParser`, planners, inspectors, report builder): deterministic logic suitable for unit tests.

## Command runner contract

`AsdfCommandRunner.run` is the only normal process-execution primitive.

It provides:

- direct executable + arguments invocation;
- concurrent stdout/stderr draining so verbose builds do not deadlock on full pipes;
- optional streamed `AsdfOutputEvent` chunks;
- a complete `AsdfCommandResult` after termination;
- Swift task cancellation that terminates the underlying process.

Output callbacks are chunks, not guaranteed lines. UI state updates from output callbacks must hop to `MainActor`. Parsers should normally consume the complete result instead of assuming one callback equals one line.

## Global write-operation policy

The app treats these as write operations:

- Project `Install Missing`;
- Versions Install / Uninstall;
- project/Home `asdf set`;
- plugin Add / Update / Update All / Remove;
- Diagnostics `reshim`.

`AppModel.hasActiveOperation` includes existing project/version tasks plus `externalWriteOperationCount`. Feature-local writers must call `beginExternalWriteOperation()` before starting and `endExternalWriteOperation()` exactly once on every completion/cancellation/failure path.

Do not add a second independent write lock. New asdf mutation workflows must join this policy.

## Projects contract

- Known project paths are persisted, but project configuration is always reread from disk.
- `.tool-versions` parsing preserves ordered fallbacks and ignores full-line/inline comments.
- A requirement is satisfied if any configured fallback is usable.
- `system` and `path:*` are treated as satisfied special values; exact/ref versions are compared with installed asdf versions.
- Missing plugins are reported as `Plugin missing`; failed installed-version lookups are `Unknown`.

### Install Missing

For each tool:

1. preserve fallback order;
2. do nothing if any fallback is already satisfied;
3. otherwise choose the first fallback with state `Missing`;
4. never auto-install a missing plugin;
5. install planned tools sequentially;
6. stream output, allow cancellation, stop on first failure;
7. cap in-memory logs at 200,000 characters;
8. refresh runtime state after success.

## Versions contract

Read commands for the selected plugin:

- `asdf list <tool>` — installed versions;
- `asdf latest <tool>` — latest stable version;
- `asdf list all <tool>` — available versions.

The Versions screen stays lazy: never run `list all` for every plugin on app launch. Search/filtering is local UI work.

Write commands:

- `asdf install <tool> <version>`;
- `asdf uninstall <tool> <version>`.

Uninstall always requires confirmation. `VersionUsageInspector` lists managed projects that exactly reference the selected tool/version, including fallback references. `.tool-versions` is never modified as a side effect of runtime install/uninstall.

## Version selection contract

Typed command:

- project: `asdf set <tool> <version>` executed with the selected project as current directory;
- Home: `asdf set -u <tool> <version>`.

Current UI writes one exact installed version or `system`, never a moving `latest` token. Project mode replaces the selected tool's existing fallback chain with that single selected value and states this before confirmation. Home settings may be overridden by nearer project `.tool-versions` files.

## Plugin management contract

Supported commands:

- `asdf plugin add <name> [<git-url>]`;
- `asdf plugin update <name> [<git-ref>]`;
- `asdf plugin update --all`;
- `asdf plugin remove <name>`.

Rules:

- The Add UI allows short-name installation but recommends an explicit Git URL because it is independent of the short-name repository.
- Plugin Add/Update/Remove use the existing streaming/cancellable process runner because Git/network work and plugin hooks may take time.
- Plugin mutations acquire the global write gate.
- Removing a plugin is destructive: asdf also removes every runtime version installed through that plugin.
- Before removal, query `asdf list <plugin>` and display every installed version that will be removed.
- `PluginRemovalInspector` also lists every managed project whose `.tool-versions` contains a requirement for that plugin, regardless of selected version/fallback.
- Removal confirmation must explain that affected project files are not rewritten; those projects will become `Plugin missing` afterward.
- If impact lookup fails, do not offer a blind destructive removal path.
- Refresh the shared AppModel after successful plugin mutations.

## Diagnostics contract

Supported diagnostics:

- `asdf info` — OS, shell, and asdf debug data;
- `asdf where <tool> [<version>]` — installation directory;
- `asdf which <command>` — resolved executable path;
- `asdf reshim <tool> <version>` — rebuild shims.

Rules:

- `info`, `where`, and `which` are read-only and may run without acquiring the write gate.
- `reshim` is treated as a write operation and must acquire the global gate.
- The Diagnostics window should expose plugin/version pickers where possible so users do not need to memorize arguments.
- Current output is copyable.
- `DiagnosticReportBuilder` produces a copyable report containing the app's active asdf version, executable path, and fresh `asdf info` output.
- Diagnostic output is transient and never persisted.

## Persistence

Persisted in `UserDefaults`:

- optional custom asdf executable path;
- managed project paths.

Not persisted:

- `.tool-versions` contents;
- plugin/runtime state;
- installed/latest/available catalogs;
- active task state/logs;
- plugin removal impact snapshots;
- diagnostics output/reports.

If App Sandbox support is introduced later, managed project paths must migrate to security-scoped bookmarks before enabling the sandbox.

## Current implementation

Implemented:

- native SwiftUI macOS executable package;
- asdf executable discovery/custom path;
- typed cancellable Process runner;
- Overview / Projects / Versions / Plugins views;
- project management and `.tool-versions` parsing;
- requirement availability and Install Missing;
- version browser, individual Install/Uninstall, usage-impact checks;
- project/Home version selection via `asdf set`;
- Plugin Manager window with Add/Update/Update All/Remove, live logs, cancellation, and removal impact;
- Diagnostics window with info/where/which/reshim and copyable diagnostic report;
- shared global write-operation gate across all mutation workflows;
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
- [x] Manual executable selection/persistence.
- [x] Streaming output and cancellation.

### Phase 2 — Projects

- [x] Add/remove project folders.
- [x] Parse `.tool-versions` and fallback chains.
- [x] Required vs installed state.
- [x] Install Missing with task log/cancel.

### Phase 3 — Version management

- [x] Installed/latest/available version queries.
- [x] Versions browser/search/filter.
- [x] General runtime Install/Uninstall.
- [x] Uninstall project-usage impact.
- [x] Project/Home `asdf set`.

### Phase 4 — Plugins and diagnostics

- [x] Plugin Add / Update / Update All / Remove.
- [x] Destructive plugin-removal impact/confirmation.
- [x] `where`, `which`, `reshim`, `info` diagnostics.
- [x] Copyable diagnostic report.

### Phase 5 — Distribution

- [ ] Decide whether to retain Swift Package app packaging or add an Xcode app project for distribution metadata.
- [ ] App icon and release-facing metadata.
- [ ] Developer ID signing and notarization.
- [ ] DMG packaging.
- [ ] Release workflow and GitHub Release automation.

## Current asdf command assumptions

Verify these against current official asdf docs before changing related code:

- `asdf plugin add <name> [<git-url>]`;
- `asdf plugin update <name> [<git-ref>]` and `asdf plugin update --all`;
- `asdf plugin remove <name>` removes the plugin and its managed package versions;
- `asdf list <tool>`, `asdf list all <tool>`, `asdf latest <tool>`;
- `asdf install <tool> <version>` and `asdf uninstall <tool> <version>`;
- `asdf set [-u] <tool> <versions...>`;
- `asdf where <tool> [<version>]`;
- `asdf which <command>`;
- `asdf reshim <tool> <version>`;
- `asdf info`.

`.tool-versions` may contain ordered fallbacks, `system`, `ref:*`, and `path:*`. Do not write `latest` into the file from the current UI.

## Codex working agreement

When asking Codex to modify this repository:

1. Read this file before editing.
2. Preserve SwiftUI/Foundation-only architecture unless explicitly changing it.
3. Keep CLI construction/parsing in `AsdfService` and process handling in `AsdfCommandRunner`.
4. Keep project disk access in `ProjectService` or a dedicated file service.
5. Put deterministic decisions in pure helpers and unit test them.
6. Reuse the global write-operation policy for every new mutation workflow.
7. Reuse the streaming/cancellable runner for potentially long commands.
8. Never silently mutate `.tool-versions`.
9. Destructive runtime/plugin removal must show known impact first.
10. Never auto-install plugins as a side effect of runtime installation.
11. Keep the Versions browser lazy; do not eagerly query every plugin's available versions.
12. Do not persist CLI-derived caches/logs unless a deliberate persistence design is documented first.
13. Update this document when architecture, commands, persistence, task policy, safety behavior, or roadmap status changes.
14. Run `swift test` and report failures before considering a change complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first and follow its architecture and safety contracts.
Implement <task> in small focused changes. Keep CLI construction in AsdfService,
process execution in AsdfCommandRunner, and project disk access in ProjectService.
Join every mutation workflow to the documented global write-operation gate.
Keep deterministic decisions in pure testable helpers, preserve destructive-action
impact confirmation, add/update tests, run swift test, and update DEVELOPMENT.md
when commands, architecture, persistence, task policy, or roadmap status changes.
```

## Design principles

- Explain state instead of merely exposing CLI buttons.
- Prefer project-centric workflows where practical.
- Preserve asdf and `.tool-versions` as sources of truth.
- Keep failure output visible and actionable.
- Make expensive or destructive behavior explicit.
- Show known impact before deletion.
