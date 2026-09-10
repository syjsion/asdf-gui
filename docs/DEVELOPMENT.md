# Development Guide

This is the architecture and safety handoff for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf. The asdf CLI and `.tool-versions` remain the sources of truth; the app is a typed UI/service layer over them.

The product should explain state and relationships, not merely mirror every CLI command as a button.

## Technical constraints

- macOS only for now; minimum macOS 14.
- Swift + SwiftUI + Foundation/AppKit where needed.
- Do not introduce React, Electron, Tauri, or WebView.
- Prefer Apple frameworks and zero third-party runtime dependencies.
- Keep normal asdf CLI construction/parsing out of SwiftUI views.
- Execute normal asdf operations with `Process.executableURL` + argument arrays; do not interpolate shell command strings.
- Destructive operations must show known impact and require explicit confirmation.
- Only one mutation/bootstrap/configuration operation may run application-wide at a time.
- Distribution stays outside the Mac App Store and remains non-App-Sandboxed.
- Do not persist copies of `.tool-versions`, plugin/runtime state, catalogs, task logs, diagnostics, resolution responses, update responses, or shell-file contents.

## Current architecture

```text
SwiftUI scenes
  -> LocalizedAppRootView
      -> missing-asdf setup / AsdfBootstrapModel
      -> main NavigationSplitView
          -> Overview
          -> ProjectsPolishedView
              -> ProjectToolVersionsManagerView
                  -> AppModel project configuration APIs
                      -> AsdfService.setVersion
                      -> ToolVersionsMutationService (delete-only exception)
          -> VersionsPolishedView
          -> ResolutionView
              -> ResolutionModel
                  -> AsdfService.current
                  -> AsdfService.shimVersions
                  -> AsdfService.whichPathInDirectory
          -> Plugins
      -> feature windows
          -> Getting Started
          -> Set Runtime Version
          -> Plugin Manager
              -> PluginDiscoveryView / PluginDiscoveryModel
          -> Diagnostics
          -> Shell Integration
          -> About + AppUpdateModel
      -> Settings / AppLanguage

Shared state/services
  -> AppModel (@MainActor)
      -> AsdfService
          -> AsdfCommandRunner
      -> ProjectService
          -> ToolVersionsParser
          -> RequirementStatusResolver
          -> ProjectInstallPlanner
      -> ToolVersionsMutationService
      -> VersionCatalog / VersionUsageInspector
      -> PluginRemovalInspector

Bootstrap
  -> AsdfBootstrapModel
      -> AsdfInstaller
          -> official asdf GitHub latest release API
          -> SHA-256 verification
          -> ~/.local/bin/asdf

Shell integration
  -> ShellIntegrationModel
      -> ShellIntegrationService
          -> ~/.zshrc or ~/.bash_profile

App updates
  -> AboutView
      -> AppUpdateModel
          -> AppUpdateChecker
              -> GitHub Releases list API
              -> semantic-version resolver
              -> architecture-specific DMG URL

Distribution
  -> SwiftPM release executable
      -> scripts/build-app.sh
      -> scripts/create-dmg.sh
      -> scripts/notarize.sh (Developer ID mode only)
      -> .github/workflows/release.yml
```

## Core responsibilities

- `LocalizedAppRootView`: app-level setup/main-navigation gate and one-time Getting Started presentation.
- `AppModel`: shared project/runtime state and application-wide mutation gate. Keep it `@MainActor`.
- `AsdfService`: typed asdf commands and deterministic output parsers.
- `AsdfCommandRunner`: process lifecycle, concurrent stdout/stderr draining, streaming, cancellation, complete result.
- `ProjectService`: project disk reads and `.tool-versions` parsing; no general-purpose writes.
- `ToolVersionsMutationService`: narrowly-scoped delete-one-tool fallback because current asdf has no delete-entry command. It is not a generic text editor.
- `ProjectsPolishedView`: card-based project presentation plus presentation-only search/sort.
- `ProjectToolVersionsManagerView`: visual management of project tool/version entries without raw file editing.
- `VersionCatalog`: installed-first merge/order of installed/available/latest runtime versions.
- `ResolutionModel`: read-only explanation of current version resolution and shim/command resolution in a selected directory.
- `PluginDiscoveryModel`: lazy read-only `asdf plugin list all` catalog lookup.
- `AppLanguage`: persisted English / Simplified Chinese preference and fallback localization.
- `AppUpdateChecker`: read-only public GitHub Release lookup.
- `ShellIntegrationService`: deterministic marker-scoped shell configuration edits.
- `AsdfInstaller`: verified official asdf binary bootstrap.
- packaging scripts: the only supported `.app` / DMG paths.

## Command runner contract

`AsdfCommandRunner.run` must:

- invoke an executable directly with argument arrays;
- concurrently drain stdout/stderr without pipe deadlocks;
- optionally stream output chunks;
- wait until both streams reach EOF before returning the final result;
- terminate the underlying `Process` when the Swift task is cancelled.

Output callbacks are chunks, not guaranteed lines. UI updates from callbacks must hop to `MainActor`.

## Global mutation policy

These operations share one application-wide gate:

- in-app asdf installation;
- Shell Integration apply/remove;
- Project `Install Missing`;
- project `.tool-versions` add/edit/reorder through `asdf set`;
- project `.tool-versions` delete-one-tool guarded fallback;
- Versions Install / Uninstall;
- project/Home `asdf set` from Set Runtime Version;
- plugin Add / Update / Update All / Remove;
- Diagnostics `reshim`.

Read-only Resolution, version catalogs, plugin discovery, update checks, and diagnostics such as `info/where/which` do not acquire the mutation gate.

Do not create a second independent write lock. Feature-local writers use `AppModel.beginExternalWriteOperation()` and release it exactly once on every path.

## asdf bootstrap contract

When no usable asdf executable is detected, show the dedicated setup UI instead of partially functional feature pages.

The installer must:

1. request `https://api.github.com/repos/asdf-vm/asdf/releases/latest` over HTTPS;
2. select the matching official macOS asset (`darwin-arm64` or `darwin-amd64`);
3. require a valid GitHub asset `sha256:` digest;
4. calculate SHA-256 locally with CryptoKit and abort on mismatch;
5. extract with direct `/usr/bin/tar` invocation;
6. accept only a regular non-symlink `asdf` file;
7. run the staged binary with `asdf version` before installation;
8. install to `~/.local/bin/asdf` without sudo/Homebrew;
9. persist/activate that exact executable through `AppModel.setExecutable`.

Never replace this flow with `curl | sh`, an unverified download, or silent shell-rc modification.

## Shell Integration contract

Current macOS support:

- Zsh -> `~/.zshrc`;
- Bash -> `~/.bash_profile`.

Managed block:

```sh
# >>> asdf GUI shell integration >>>
export PATH='<active-asdf-directory>':"$PATH"
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
# <<< asdf GUI shell integration <<<
```

Rules:

- Preview target file and exact block before writing.
- Never modify text outside the two markers.
- If both markers are absent, append exactly one block.
- If both exist and the active executable changes, replace only the managed block.
- One-sided/malformed markers are an error; never guess.
- Apply/remove rereads the file and fails if it changed since preview generation.
- Preserve POSIX permissions after atomic writes when possible.
- Remove Integration deletes only the app-owned block.
- Do not silently add completions or unsupported shell syntax.

## Localization contract

Supported app languages:

- English (`en`)
- Simplified Chinese (`zh-Hans`)

Behavior:

- first default follows `Locale.preferredLanguages`;
- explicit selection is persisted under `AppLanguage.storageKey`;
- language switching applies without restart;
- major scene roots receive `\.locale` derived from `AppLanguage`;
- packaged builds include `zh-Hans.lproj/Localizable.strings`;
- `AppLanguage.localized` first uses the packaged strings table and then falls back to the in-code Simplified Chinese map when a newly introduced dynamic key is not yet consolidated into the table;
- runtime `String` values and dynamically selected labels must explicitly use the selected `AppLanguage`.

When adding visible UI, update the packaged localization table when practical and always provide a working Simplified Chinese path before merging. Raw asdf command output remains raw and is not translated/persisted.

## Projects contract

### General project state

- Persist only managed project paths; reread `.tool-versions` from disk.
- Preserve ordered fallbacks and ignore comments when interpreting requirements.
- A requirement is satisfied if any configured fallback is usable.
- `system` and `path:*` are satisfied special values.
- Missing plugins show `Plugin missing`; lookup failures show `Unknown`.
- `Install Missing` never auto-installs plugins, installs sequentially, streams logs, supports cancellation, stops on first failure, and refreshes after success.
- The main Projects UI remains card-based (`ScrollView` + `LazyVStack`).
- Search is presentation-only and matches project name, path, and configured tool names.
- Sort is presentation-only; current choices are Name, Path, and Tool count. Sorting/searching must never mutate persisted project order or project files.

### `.tool-versions` management

Users never receive a raw editable text view for the whole file.

Normal writes use:

```text
asdf set <tool> <version> [<version>...]
```

with `currentDirectoryURL` set to the managed project. This covers file creation, add, edit, fallback insertion/removal, and fallback reordering. Version tokens must be individual asdf values and the selected fallback order must be passed unchanged.

### Delete-one-tool exception

As of asdf 0.20, the CLI has no command to remove one tool entry from `.tool-versions`. Do not fake deletion using `system`, an empty list, or an invented command.

`ToolVersionsMutationService` is the only permitted direct `.tool-versions` writer and only for deleting one tool line after explicit confirmation. It must reread before mutation, reject duplicate target entries, verify expected ordered versions, preserve unrelated content/comments/permissions, write atomically, and refresh state afterward.

## Versions contract

Read commands:

- `asdf list <tool>`;
- `asdf latest <tool>`;
- `asdf list all <tool>`.

Catalogs stay lazy. `VersionCatalog.records` ordering is:

1. all locally installed versions in asdf-returned order;
2. remaining available versions in upstream order;
3. latest if absent;
4. no duplicates.

Writes:

- `asdf install <tool> <version>`;
- `asdf uninstall <tool> <version>`.

Uninstall always requires confirmation and `VersionUsageInspector` lists managed-project references.

## Version selection contract

- Project: `asdf set <tool> <version>` in the selected project directory.
- Home: `asdf set -u <tool> <version>`.

These writes use the global mutation gate. Project mode replaces the selected tool's existing fallback chain and explains the impact before confirmation.

## Resolution and shim contract

The Resolution page exists to explain asdf's effective behavior, especially Home/project inheritance and shim confusion.

Supported read commands:

```text
asdf current [<tool>]
asdf which <command>
asdf shimversions <command>
```

Rules:

- `asdf current` and `asdf which` must execute with `currentDirectoryURL` set to the selected Home/project context. Their answer depends on directory traversal of `.tool-versions`.
- `shimversions` is context-independent and lists every installed plugin/version that provides the command.
- `parseCurrent` treats the modern asdf output as aligned columns: Name, Version, Source, Installed.
- Split aligned columns only on tabs or runs of 2+ whitespace so a Source path containing a single space and a Version field containing fallback values remain intact.
- The Source column may be absent/blank; do not invent a path.
- Installed is a boolean from asdf and should be shown explicitly instead of inferred from local caches.
- Resolution is read-only and transient; do not persist results.
- Prefer this explanatory workflow over adding a generic terminal.
- Do not expose unrestricted `asdf exec` as a default GUI feature. If a future feature needs execution, define a constrained product workflow and threat model first.

## Plugin management and discovery contract

Supported commands:

```text
asdf plugin list all
asdf plugin add <name> [<git-url>]
asdf plugin update <name> [<git-ref>]
asdf plugin update --all
asdf plugin remove <name>
```

`plugin list all` is a read-only, lazy catalog operation. The discovery UI searches short name and URL locally after loading the catalog. Installing from a catalog result should pass the returned Git URL to the existing add-plugin workflow when available; this follows asdf's recommendation to prefer explicit Git URLs over short-name lookup.

Plugin mutations use the streaming/cancellable runner and global gate. Before removal, query installed versions and managed-project impact. Plugin removal never rewrites project files.

## Diagnostics contract

Supported diagnostics:

- `asdf info`;
- `asdf where <tool> [<version>]`;
- `asdf which <command>`;
- `asdf reshim <tool> <version>`.

`info`, `where`, and `which` are reads. `reshim` is a write and uses the global gate. Resolution's directory-aware `which` is separate from the generic diagnostic lookup.

## App update-check contract

The About window performs automatic-on-open and manual update checking using `GET /repos/syjsion/asdf-gui/releases`, not `/releases/latest`, because current ad-hoc releases are prereleases. Compare `vMAJOR.MINOR.PATCH` numerically, ignore drafts, include prereleases, select architecture-specific DMGs, and never auto-install or silently replace the running app.

## Persistence

Persisted small preferences:

- optional custom/GUI-installed asdf executable path;
- managed project paths;
- whether Getting Started was presented;
- selected app language.

Not persisted:

- `.tool-versions` contents;
- shell configuration contents/plans;
- plugin/runtime state and catalogs;
- resolution/shim results;
- active task logs;
- diagnostics;
- update-check responses.

## Distribution contract

The project stays SwiftPM-based. Do not add an Xcode project solely for packaging unless a future capability requires it.

Bundle metadata:

- app name: `asdf GUI`;
- bundle identifier: `io.github.syjsion.asdf-gui`;
- minimum macOS: 14.0;
- non-App-Sandboxed;
- app icon generated by `scripts/generate-app-icon.py`;
- localizations: English + Simplified Chinese.

Release modes:

- `adhoc`: no Apple credentials; prerelease DMGs; no notarization/Gatekeeper trust claim.
- `developer-id`: all Apple credentials present; Developer ID + Hardened Runtime + timestamp + `notarytool` + stapling.

Partial Apple credentials fail closed. Both arm64 and x86_64 artifacts must succeed. See `docs/RELEASING.md`.

## Roadmap

### Phase 1 — Foundation
- [x] Native SwiftUI navigation.
- [x] Typed Process/service boundary.
- [x] asdf detection/version/plugins.
- [x] executable selection/persistence.
- [x] streaming output/cancellation.

### Phase 2 — Projects
- [x] Add/remove project folders.
- [x] Parse `.tool-versions` + fallbacks.
- [x] Required vs installed state.
- [x] Install Missing with logs/cancel.
- [x] Card-based layout.
- [x] Visual `.tool-versions` management.
- [x] Add/edit/reorder through `asdf set`.
- [x] Guarded delete-one-tool fallback.

### Phase 3 — Version management
- [x] Installed/latest/available queries.
- [x] Versions browser/search/filter.
- [x] Installed-first catalog ordering.
- [x] Runtime Install/Uninstall + usage impact.
- [x] Project/Home `asdf set`.

### Phase 4 — Plugins and diagnostics
- [x] Plugin Add / Update / Update All / Remove.
- [x] plugin-removal impact/confirmation.
- [x] `where`, `which`, `reshim`, `info`.
- [x] copyable diagnostic report.

### Phase 5 — Distribution
- [x] SwiftPM app bundle + DMG.
- [x] arm64 + x86_64 artifacts/checksums.
- [x] ad-hoc prerelease mode.
- [x] optional Developer ID/notarization mode.
- [x] release automation.
- [ ] smoke-test downloaded ad-hoc build on a real Mac.
- [ ] later smoke-test a notarized release.

### Phase 6 — Onboarding and product hardening
- [x] missing-asdf setup + verified installer.
- [x] Shell Integration.
- [x] Getting Started.
- [x] English / Simplified Chinese switch.
- [x] About/version/update check.
- [x] Projects layout repair.
- [x] Versions installed-first UX.
- [x] Project search/sort.
- [ ] Shell completion helper / more shells if deliberately designed.

### Phase 7 — Resolution and discovery
- [x] Project/Home effective version resolver via `asdf current`.
- [x] Directory-aware executable resolution via `asdf which`.
- [x] Shim provider explorer via `asdf shimversions`.
- [x] Searchable plugin discovery via `asdf plugin list all`.
- [ ] Explain legacy-version-file resolution when enabled.
- [ ] Optional constrained environment inspector around `asdf env`.

## Codex working agreement

When using Codex on this repository:

1. Read `docs/DEVELOPMENT.md`; for release changes also read `docs/RELEASING.md`.
2. Preserve SwiftUI/Foundation architecture unless explicitly changing it.
3. Keep normal asdf CLI construction/parsing in `AsdfService` and process handling in `AsdfCommandRunner`.
4. Keep project reads in `ProjectService`; do not introduce a generic project-file writer.
5. Put deterministic decisions/parsers in pure helpers and test them.
6. Reuse the global mutation gate for every new write/bootstrap/configuration workflow.
7. Reuse streaming/cancellation for potentially long commands.
8. Never expose a raw editable `.tool-versions` editor as the normal path.
9. For `.tool-versions` add/edit/reorder use `asdf set`; keep direct mutation delete-only and guarded.
10. Show known impact before destructive runtime/plugin removal.
11. Keep version catalogs lazy and installed-first.
12. Keep plugin discovery lazy; use catalog Git URLs when available.
13. Preserve directory context for `asdf current` and directory-aware `which`.
14. Preserve `parseCurrent` tests for fallback values and source paths containing spaces.
15. Do not add unrestricted `asdf exec` merely to increase command coverage.
16. Preserve verified asdf bootstrap and Shell Integration safety contracts.
17. Keep English and Simplified Chinese paths working for every new major UI.
18. App update checking includes prereleases and remains read-only.
19. Preserve SwiftPM packaging and both release architectures.
20. Never commit Apple credentials or claim ad-hoc artifacts are notarized.
21. Update this document when architecture, commands, mutation policy, localization, persistence, or distribution changes.
22. Run `swift test` and package verification before considering a change complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first; for release work also read docs/RELEASING.md.
Preserve SwiftUI/Foundation, the global mutation gate, bilingual UI, installed-first
catalogs, guarded .tool-versions mutation, directory-aware resolution, and release
contracts. Prefer explanatory typed asdf workflows over raw CLI mirroring. Do not add
an unrestricted asdf exec terminal. Add tests, run swift test and package verification,
and update DEVELOPMENT.md when behavior or architecture changes.
```

## Design principles

- Explain state instead of exposing raw CLI buttons.
- Prefer project-centric workflows.
- Preserve asdf and `.tool-versions` as sources of truth.
- Prefer asdf's own commands for writes whenever the CLI supports the operation.
- Make direct file mutations narrow, explicit, guarded, and tested.
- Keep failure output visible and actionable.
- Make destructive effects explicit before execution.
- Favor native macOS layout behavior over web-style abstractions.
