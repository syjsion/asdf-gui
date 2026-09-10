# Development Guide

This is the handoff/reference for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf. The asdf CLI and `.tool-versions` remain the sources of truth; the app is a typed UI/service layer over them.

## Technical constraints

- macOS only for now.
- Swift + SwiftUI + Foundation/AppKit where needed. Do not introduce React, Electron, Tauri, or WebView.
- Prefer Apple frameworks and zero third-party runtime dependencies unless a dependency clearly reduces maintenance risk.
- Keep CLI construction/parsing out of SwiftUI views.
- Run normal asdf commands with `Process.executableURL` + argument arrays; do not construct `/bin/zsh -c` command strings.
- Destructive operations must show known impact and require explicit confirmation.
- Only one asdf write operation may run application-wide at a time.
- Distribution is outside the Mac App Store: non-App-Sandbox + Developer ID + Hardened Runtime + Apple notarization + DMG.
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

Distribution
  -> SwiftPM release executable
      -> scripts/build-app.sh
          -> .app bundle + Info.plist + generated AppIcon.icns
          -> ad-hoc signature in CI OR Developer ID + Hardened Runtime
      -> scripts/create-dmg.sh
          -> compressed DMG + Applications shortcut
      -> scripts/notarize.sh
          -> notarytool + stapler
      -> .github/workflows/release.yml
          -> arm64 + x86_64 DMGs
          -> SHA256SUMS.txt
          -> GitHub Release
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
- `scripts/build-app.sh`: the single source of truth for turning the SwiftPM release executable into the distributable `.app` structure. Do not create a second packaging path in CI.
- `scripts/create-dmg.sh`: the single DMG assembly path for local verification and releases.
- `scripts/notarize.sh`: the single command-line notarization/stapling helper.
- `docs/RELEASING.md`: operational signing/notarization/release runbook; keep it synchronized with release scripts/workflows.

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

## Distribution contract

The distribution path deliberately stays SwiftPM-based. Do **not** introduce an Xcode project solely for bundling/signing unless a future feature requires Xcode-managed capabilities or build settings that the current scripts cannot maintain cleanly.

### App bundle

`packaging/Info.plist` contains stable app metadata. `scripts/build-app.sh` copies the SwiftPM release executable into:

```text
asdf GUI.app/
  Contents/
    Info.plist
    MacOS/asdf-gui
    Resources/AppIcon.icns
```

Release metadata:

- bundle identifier: `io.github.syjsion.asdf-gui`;
- display name: `asdf GUI`;
- deployment target: macOS 14.0;
- `CFBundleShortVersionString`: release tag version without the leading `v`;
- `CFBundleVersion`: CI run number (or explicit local `BUILD_NUMBER`).

`AppIcon.icns` is generated reproducibly from `scripts/generate-app-icon.py`; generated PNG/ICNS files are build outputs and are not committed.

### Signing and sandbox policy

- Public releases use a **Developer ID Application** certificate.
- Public app signatures must use Hardened Runtime and a secure timestamp.
- `packaging/asdf-gui.entitlements` is intentionally empty.
- Do not add `com.apple.security.app-sandbox`; the app must continue to launch the user's local `asdf` binary and work with selected project folders under the current architecture.
- Do not add Hardened Runtime exception entitlements unless a concrete feature requires one and the reason is documented.
- CI pull-request packaging uses an ad-hoc signature only to validate bundle assembly. Ad-hoc artifacts must never be published as releases.

### Notarization

- Custom notarization uses `xcrun notarytool`; do not use deprecated `altool`.
- Release CI authenticates to notarization with an App Store Connect API key supplied as GitHub Actions secrets.
- The signed app is zipped, submitted, and stapled first.
- The stapled app is placed in the DMG; the DMG is signed, submitted, and stapled separately.
- Gatekeeper/codesign/stapler verification must pass before release publication.

### DMG and architectures

`scripts/create-dmg.sh` creates a compressed UDZO disk image containing:

- `asdf GUI.app`;
- an `Applications` symlink for drag-and-drop installation.

Release CI builds separately on Apple Silicon and Intel runners. Published names are:

```text
asdf-gui-X.Y.Z-macos-arm64.dmg
asdf-gui-X.Y.Z-macos-x86_64.dmg
SHA256SUMS.txt
```

Do not silently drop an architecture from the release matrix; document any support-policy change first.

### GitHub Release policy

- Public releases are triggered only by tags matching `vMAJOR.MINOR.PATCH`; the workflow validates exact semantic-version form before building.
- Release jobs fail if any required Apple signing/notarization secret is missing. There is no unsigned fallback.
- Both architecture jobs must pass before the publish job creates the GitHub Release.
- The publish job uses the repository-scoped `GITHUB_TOKEN` with `contents: write`; Apple credentials remain confined to macOS package jobs.
- Release notes are generated by GitHub and SHA-256 checksums are attached with the DMGs.

See `docs/RELEASING.md` for secret names, local package-check commands, and operational troubleshooting.

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
- reproducible SwiftPM -> `.app` packaging with Info.plist and generated ICNS;
- ad-hoc packaging verification in CI;
- Developer ID + Hardened Runtime signing automation;
- `notarytool` app/DMG notarization and stapling automation;
- signed DMG packaging with Applications shortcut;
- tag-driven arm64/x86_64 GitHub Release workflow with checksums;
- macOS GitHub Actions CI running `swift test` plus package verification.

Run locally:

```bash
swift test
swift run asdf-gui
```

Build an ad-hoc local app/DMG using the commands in `docs/RELEASING.md`. Xcode can still open `Package.swift` directly.

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

- [x] Retain Swift Package architecture and add reproducible app-bundle packaging.
- [x] App icon and release-facing Info.plist metadata.
- [x] Developer ID / Hardened Runtime signing automation.
- [x] Apple `notarytool` notarization/stapling automation.
- [x] DMG packaging and verification.
- [x] Apple Silicon + Intel release artifacts.
- [x] Tag-driven GitHub Release automation with checksums.
- [ ] Configure real Apple signing/notarization secrets in repository settings.
- [ ] Publish and smoke-test the first signed public release.

The final two items are operational prerequisites/actions, not missing application code. Never store the required credentials in the repository.

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
13. Preserve the SwiftPM-based distribution path; update `scripts/build-app.sh`, `scripts/create-dmg.sh`, and `docs/RELEASING.md` together when packaging changes.
14. Never commit Developer ID certificates, `.p8` keys, passwords, or notarization credentials. Release credentials belong only in GitHub Actions secrets or an equivalent secure store.
15. Public releases must remain Developer ID-signed, Hardened Runtime-enabled, notarized, stapled, and verified; do not add an unsigned fallback.
16. Keep both arm64 and x86_64 release outputs unless the supported-architecture policy is deliberately changed and documented.
17. Update this document when architecture, commands, persistence, task policy, safety behavior, distribution behavior, or roadmap status changes.
18. Run `swift test` and the ad-hoc package verification before considering distribution changes complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md and docs/RELEASING.md first and follow their architecture,
safety, and distribution contracts. Implement <task> in small focused changes.
Keep CLI construction in AsdfService, process execution in AsdfCommandRunner,
and project disk access in ProjectService. Join every mutation workflow to the
global write-operation gate. Preserve impact confirmation for destructive actions.
For packaging changes, keep the SwiftPM app-bundle path reproducible, never commit
Apple credentials, and keep signing/notarization verification strict. Add/update
tests, run swift test and package verification, and update documentation when the
architecture, commands, persistence, task policy, or distribution behavior changes.
```

## Design principles

- Explain state instead of merely exposing CLI buttons.
- Prefer project-centric workflows where practical.
- Preserve asdf and `.tool-versions` as sources of truth.
- Keep failure output visible and actionable.
- Make expensive or destructive behavior explicit.
- Show known impact before deletion.
- Keep packaging reproducible and credentials out of source control.
- Fail closed on release signing/notarization problems rather than publishing weaker artifacts.
