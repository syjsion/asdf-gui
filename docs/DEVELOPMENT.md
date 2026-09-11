# Development Guide

This is the architecture and safety handoff for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf. The asdf CLI, `.tool-versions`, machine-level `.asdfrc`, and explicit shell configuration remain the sources of truth. Prefer GUI workflows that explain state and reduce cognitive load instead of mirroring every CLI command as a button.

## Technical constraints

- macOS only; minimum macOS 14.
- Swift + SwiftUI + Foundation/AppKit where needed.
- No React, Electron, Tauri or WebView.
- Prefer Apple frameworks and zero third-party runtime dependencies.
- Normal asdf command construction/parsing belongs in `AsdfService`, never SwiftUI views.
- Execute commands with `Process.executableURL` + argument arrays; no normal-operation shell-string interpolation.
- Only one mutation/bootstrap/configuration operation may run application-wide at a time.
- Destructive operations show known impact and require explicit confirmation.
- Distribution remains non-App-Sandboxed and outside the Mac App Store for now.
- Do not persist runtime/plugin catalogs, runtime-storage scan results, health reports, diagnostics, environment output, update responses or task logs.

## Architecture

```text
SwiftUI
  -> LocalizedAppRootView
      -> Overview / Project Health
      -> Projects / ProjectToolVersionsManager
          -> ProjectActivityModel
          -> ProjectListPlanner
      -> Versions / RuntimeUpdateCenter / RuntimeStorageView
          -> RuntimeStorageModel
          -> RuntimeStorageSizer
      -> Resolution / shims / EnvironmentInspector
      -> Plugins / Plugin Manager / Discovery
      -> feature windows:
         Getting Started, Set Runtime Version, Diagnostics,
         Shell Integration, Shell Completions, asdf Configuration,
         About, Settings

Shared UI state
  -> AppNavigationModel (@MainActor)
      -> current AppSection
      -> one-shot Project and Versions deep links

Shared asdf state
  -> AppModel (@MainActor)
      -> AsdfService
          -> AsdfCommandRunner
      -> ProjectService
      -> ToolVersionsMutationService

Structured file services
  -> AsdfConfigService
  -> ShellIntegrationService
  -> ShellCompletionService

Read-only / feature models
  -> ResolutionModel
  -> EnvironmentInspectorModel
  -> RuntimeUpdateCenterModel
  -> RuntimeStorageModel
  -> ProjectHealthModel
  -> PluginDiscoveryModel
```

## Command runner contract

`AsdfCommandRunner.run` invokes executables directly, drains stdout/stderr concurrently, supports streamed output, waits for both streams to reach EOF, and terminates the underlying `Process` when the Swift task is cancelled. Output callbacks are chunks rather than guaranteed lines; UI updates from callbacks hop to MainActor.

## Global mutation gate

All writes share `AppModel.beginExternalWriteOperation()` / `endExternalWriteOperation()` or an existing AppModel task participating in that same gate:

- in-app asdf installation;
- Shell Integration apply/remove;
- Shell Completions apply/remove;
- structured `.asdfrc` save;
- Project Install Missing;
- project `.tool-versions` add/edit/reorder;
- guarded delete-one-tool fallback;
- runtime Install / Uninstall;
- Project / Parent / Home `asdf set`;
- plugin Add / Update / Update All / Remove;
- Diagnostics `reshim`.

Runtime Storage measurement is read-only and does not acquire the write gate. Cleanup from Runtime Storage must reuse the existing runtime Uninstall operation and therefore does use the same gate. Do not add a second independent write lock.

## asdf bootstrap

When no usable asdf executable is detected, use the setup UI. The installer downloads the official macOS release asset, selects the current architecture, requires GitHub's SHA-256 digest, verifies it locally, extracts without shell piping, verifies the staged binary with `asdf version`, installs only to `~/.local/bin/asdf`, and persists that exact executable path. Never replace this with `curl | sh`, an unverified download or silent shell-rc changes.

## Shell Integration

Shell Integration manages only PATH/shims:

- Zsh -> `~/.zshrc`
- Bash -> `~/.bash_profile`

Only the app-owned marker block may be added/replaced/removed. Always preview before writing, reject malformed/one-sided markers, reread before mutation to detect races, write atomically, preserve permissions when possible, and never silently add completions.

## Shell Completions

Shell Completions is a separate explicit workflow. Do not make completion changes a side effect of Shell Integration.

Use the current asdf binary completion interface, not legacy `asdf.sh` completion sourcing.

### Bash

- completion configuration file is `~/.bashrc` (distinct from the Bash PATH integration file `~/.bash_profile`);
- manage only the dedicated asdf GUI completion marker block;
- use the exact executable selected by the GUI, equivalent to `. <('/absolute/path/to/asdf' completion bash)`;
- do not silently modify `.bash_profile` to source `.bashrc`; the UI may explain that macOS login-shell setups can require this relationship.

### Zsh

- generate completion text through typed `asdf completion zsh`;
- use `${ASDF_DATA_DIR}/completions` only when inherited `ASDF_DATA_DIR` is absolute, otherwise `~/.asdf/completions`;
- write generated output to `<completion-dir>/_asdf`;
- manage only the app-owned `fpath` / `compinit` marker block in `~/.zshrc`;
- compare the current `_asdf` file with fresh `asdf completion zsh` output so an asdf upgrade can surface `needsUpdate`.

### Completion write safety

1. preview the exact shell marker block before Apply;
2. reread the shell rc file before mutation and require byte-for-byte equality with the preview snapshot;
3. for Zsh, reread `_asdf` too and reject the write if it changed after preview;
4. create the completion directory when needed and preserve existing file permissions where practical;
5. completion Apply/Remove participates in the global mutation gate;
6. Remove deletes only the GUI-owned shell marker block;
7. never delete `_asdf` during Remove because another shell framework may also reference it;
8. keep completion configuration independent from the PATH/shims marker block.

## Structured `.asdfrc` management

asdf 0.20 machine configuration is `${HOME}/.asdfrc` by default; absolute `ASDF_CONFIG_FILE` overrides that location. The GUI may manage only the six documented standard keys:

```text
legacy_version_file = no
use_release_candidates = no
always_keep_download = no
plugin_repository_last_check_duration = 60
disable_plugin_short_name_repository = no
concurrency = auto
```

Rules:

- boolean values are `yes` / `no`;
- repository sync is `0`, `never`, or a positive integer;
- concurrency is `auto` or a positive integer;
- surface inherited `ASDF_CONCURRENCY` because it overrides the saved value;
- no raw config editor;
- duplicate/invalid managed keys are errors;
- preserve comments, unknown settings, plugin hooks and inline comments;
- reread before save, write atomically, preserve permissions where possible;
- saving uses the global mutation gate.

## Localization

Supported languages are English (`en`) and Simplified Chinese (`zh-Hans`). The preference is persisted under `AppLanguage.storageKey` and switching applies without restart. New visible UI, keyboard guidance and accessibility copy must work in both languages. Raw asdf output is never translated or persisted.

## Navigation, keyboard and accessibility

`AppNavigationModel` is the single shared source of truth for the main sidebar and cross-feature deep links. Do not introduce an independent main-section selection in feature views.

Stable main shortcuts:

```text
Command-1  Overview
Command-2  Projects
Command-3  Versions
Command-4  Resolution
Command-5  Plugins
Command-Shift-C  Shell Completions
```

Deep-link rules:

- `showProject(_:)` selects Projects and creates a one-shot project search request;
- `showVersions(tool:)` selects Versions and creates a one-shot tool-selection request;
- destination views consume requests once and clear them;
- deep-link state is transient and never persisted.

Keyboard rules:

- dense/search workflows should place initial focus on the highest-value search/input field when predictable;
- destructive actions must never be the default Return action;
- Plugin Discovery supports focused search, native table selection, and an explicit `Install Selected` default action;
- modal/secondary windows should provide a predictable Escape/cancel path when possible;
- `.tool-versions` editing keeps Return for safe Save/default actions and Enter-on-field behavior for adding explicit values.

Accessibility rules:

- never communicate health/runtime state by color alone; pair it with visible status text;
- important icon-only or ambiguous controls need accessibility labels/hints;
- version rows expose version + installed/latest/available status to VoiceOver;
- project runtime rows expose tool + version + status/fallback semantics;
- project favorite state, recent-use state, storage size and managed-project references need textual/VoiceOver semantics;
- decorative status/folder icons should be hidden when adjacent text already conveys the meaning;
- completion status and target file paths must be available as text, not inferred from icon/color.

## Projects and `.tool-versions`

Persist managed project paths and reread project configuration from disk. Preserve ordered fallbacks. A requirement is satisfied if any fallback is usable; `system` and `path:*` are satisfied special values. Missing plugins and lookup failures remain distinct states.

Normal writes use asdf itself:

```text
asdf set <tool> <version> [<version>...]
```

Run from the selected project directory. This covers first-file creation, add, edit and fallback reorder/removal. Version tokens are validated and passed in exact user-selected order. Project cards may expose read-only conveniences such as Reveal in Finder without using the mutation gate.

### Project favorites and recent activity

Project favorites and recent-use timestamps are UI preferences, not asdf state. They are intentionally small UserDefaults-backed metadata keyed by the standardized managed-project path.

Rules:

- favorites may affect presentation order/filtering only; they never change project files or asdf state;
- favorites are pinned ahead of the selected normal sort while the All scope is active;
- Favorites scope shows only favorite managed projects;
- Recently Used sort orders projects by the timestamp of explicit project actions, then falls back to name;
- update recent-use time only for deliberate interactions such as opening `.tool-versions`, Reveal in Finder, or Install Missing; do not mark every background refresh as activity;
- removing a managed project also removes its favorite/recent metadata;
- prune stale favorite/recent paths that are no longer managed;
- deep-linking to Projects resets the Favorites-only scope so the requested project cannot be hidden by a UI filter;
- do not persist search text or sort/filter selection unless a future product decision explicitly requires it.

### Delete-one-tool exception

asdf 0.20 has no CLI command to delete one tool entry. `ToolVersionsMutationService` is the only direct `.tool-versions` writer and only deletes one matching tool line after explicit confirmation. It must reread the file, require exactly one target, verify ordered versions still match the UI snapshot, preserve unrelated content/comments, write atomically, restore permissions where possible, and abort on duplicate/stale targets. Never evolve it into a general text editor.

## Version browser and updates

Read commands are `asdf list <tool>`, `asdf list all <tool>`, and `asdf latest <tool>`. `VersionCatalog.records` remains installed-first: installed versions in asdf order, remaining available versions, then latest if absent, with no duplicates.

Runtime Install/Uninstall uses exact versions. Uninstall shows project usage impact first and never rewrites `.tool-versions`. Versions honors `AppNavigationModel.showVersions(tool:)` before loading the requested catalog.

Runtime Update Center is on-demand. It installs the resolved exact latest version only; never write `latest` into `.tool-versions`, uninstall old versions automatically, or switch Project/Parent/Home configuration automatically.

### Runtime Storage

Runtime Storage is an on-demand visibility/cleanup workflow for the currently selected installed plugin.

For each installed version:

1. resolve the install directory through typed `asdf where <tool> <version>`;
2. measure the returned path using Foundation only;
3. run filesystem traversal off the main actor;
4. count regular files and sum allocated file size;
5. do not follow nested symbolic links, so external targets are not traversed or double-counted;
6. surface per-version lookup/measurement errors instead of failing the entire scan;
7. show managed-project references using the existing `VersionUsageInspector`/`projectsUsing` behavior.

Safety rules:

- scans never run during normal app startup;
- scan results are transient and never persisted;
- the scanner never deletes files or directories;
- Reveal in Finder is read-only;
- cleanup must call the existing `uninstallVersionFromBrowser` / typed `asdf uninstall <tool> <version>` path;
- cleanup keeps the existing project-impact confirmation and global write gate;
- never add an optimization that recursively deletes asdf runtime directories directly, even when a path was returned by `asdf where`;
- after an uninstall changes installed-version state, rescan the selected plugin rather than assuming the old byte count remains valid.

## Version selection and inheritance

Supported scopes:

```text
Project: asdf set <tool> <version>
Parent:  asdf set -p <tool> <version>
Home:    asdf set -u <tool> <version>
```

Project and Parent commands run in the managed project directory. `ParentToolVersionsLocator` is preview-only and identifies the closest ancestor `.tool-versions`; if none exists, Parent scope is unavailable. The actual Parent write remains `asdf set -p`. Persist exact versions or explicit values such as `system`, never moving aliases such as `latest`.

## Resolution, shims and environment

Read-only commands include:

- `asdf current [tool]`
- `asdf which <command>` in a selected directory
- `asdf shimversions <command>`
- `asdf env <command>` in a selected directory

Resolution explains why a project resolves a version/executable. Environment Inspector only wraps shimmed-command `asdf env`; never turn it into arbitrary command execution. Environment parsing splits on the first `=` because values may contain `=`. These scans are user-triggered and transient.

## Project Health and repair actions

Project Health is on-demand and combines snapshots with `asdf current` per project. Surface unreadable/empty configuration, missing plugins, missing runtimes when no fallback is usable, unknown lookup state, effective runtimes reported not installed, and inherited source paths.

Repair policy:

- no automatic Fix All;
- only deterministic issues receive an action;
- plugin repair loads `asdf plugin list all` only after the user requests repair, exact-name matches only, and prefers an explicit catalog Git URL;
- if no usable exact catalog URL exists, confirmation must explicitly state short-name fallback;
- runtime repair installs the first configured fallback whose state is exactly `.missing`;
- repair never rewrites Project/Parent/Home `.tool-versions`;
- reuse existing operation models, logs, cancellation and global gate;
- uncertain states never guess a repair;
- offer contextual navigation to Projects, Versions or Plugin Manager where useful.

## Plugins

Supported management commands:

```text
asdf plugin add <name> [<git-url>]
asdf plugin update <name> [<git-ref>]
asdf plugin update --all
asdf plugin remove <name>
asdf plugin list all
```

Discovery is lazy/searchable and exact-name matching is required when resolving catalog entries for automated repair. Before removal, list installed runtime versions and managed-project impact; if impact lookup fails, do not offer blind removal.

## Diagnostics

Supported diagnostics are `asdf info`, `asdf where`, `asdf which` and `asdf reshim`. `info`/`where`/`which` are reads; `reshim` is a write using the global gate. Diagnostic output is transient/copyable. Do not add unrestricted `asdf exec` merely for command coverage.

## App updates

About uses the public GitHub Releases list rather than `/releases/latest` because current ad-hoc builds are prereleases. Compare semantic versions numerically, include prereleases, select the current architecture's DMG when available, and remain read-only. Never silently replace the running app.

## Persistence

Persist only small preferences:

- optional selected/GUI-installed asdf path;
- managed project paths;
- favorite project paths;
- per-managed-project recent-use timestamps;
- Getting Started presentation state;
- selected language.

`.asdfrc`, shell rc files and generated completions remain file sources of truth and are reread when their management UI opens/refreshes. Runtime storage measurements, navigation requests, searches and operation logs are transient.

## Distribution

The project remains SwiftPM-based. Packaging uses `scripts/build-app.sh`, `scripts/create-dmg.sh`, optional `scripts/notarize.sh`, and `.github/workflows/release.yml`. Bundle ID is `io.github.syjsion.asdf-gui`, minimum macOS is 14, and the app is non-App-Sandboxed.

Release modes:

- `adhoc`: no Apple credentials, prerelease DMGs, no notarization/Gatekeeper trust claim;
- `developer-id`: complete credentials, Developer ID + Hardened Runtime + timestamp + `notarytool` + stapling.

Partial credentials fail closed. Both arm64 and x86_64 artifacts must succeed. See `docs/RELEASING.md`.

## Roadmap status

Completed foundation includes native SwiftUI architecture, project `.tool-versions` management, project Favorites/Recently Used presentation, runtime/plugin management and discovery, on-demand Runtime Storage with guarded cleanup, diagnostics, bootstrap, Shell Integration, Shell Completions for Zsh/Bash, bilingual UI, About/update checking, Resolution/shim/environment tooling, Parent inheritance editing, Runtime Update Center, Project Health and deterministic repairs, structured `.asdfrc`, shared navigation/deep links, keyboard section shortcuts, Plugin Discovery keyboard workflow, Finder reveal, and growing VoiceOver/status accessibility support.

Still valuable future work:

- operation history / recent mutation summaries without persisting raw command output;
- deeper keyboard navigation for dense `.tool-versions` and versions tables;
- broader VoiceOver/accessibility audit on every feature window;
- Fish/other-shell completion support if current asdf semantics justify it;
- real-Mac smoke testing;
- Developer ID/notarized release when credentials exist.

## Codex working agreement

When using Codex:

1. Read this file; for release work also read `docs/RELEASING.md`.
2. Preserve SwiftUI/Foundation architecture and the single global mutation gate.
3. Keep asdf CLI construction/parsing in `AsdfService` and process lifecycle in `AsdfCommandRunner`.
4. Keep normal `.tool-versions` writes behind `asdf set`; preserve the guarded delete-one-tool exception.
5. Keep `.asdfrc` management structured and limited to documented keys.
6. Keep Shell Integration and Shell Completions as separate marker-owned workflows.
7. Bash completion belongs in `.bashrc`; Bash PATH integration remains `.bash_profile`.
8. Zsh completion must be generated by typed `asdf completion zsh`, race-check both files, and never delete `_asdf` on Remove.
9. Keep Favorites/Recently Used as UI-only path metadata; never let them mutate asdf/project files.
10. Keep Runtime Storage on-demand and read-only except for cleanup routed through existing typed `asdf uninstall`; never directly delete runtime directories.
11. Keep version catalogs lazy and installed-first.
12. Parent scope previews the nearest parent but writes through `asdf set -p`.
13. Update Center installs exact latest versions only; no automatic config rewrite or old-version deletion.
14. Environment Inspector only wraps shimmed-command `asdf env`.
15. Health scans on demand, treats any usable fallback as satisfied, and uses deterministic per-issue repairs only.
16. Preserve `AppNavigationModel`, stable Command-1...5 semantics, predictable default/cancel actions and bilingual keyboard guidance.
17. New status UI must not rely on color alone; preserve VoiceOver labels/hints for important controls.
18. Do not weaken bootstrap checksums, shell/config race protection, destructive confirmations or release-mode safety.
19. Add/update tests for parsers, file mutation policy, project presentation decisions and runtime storage measurement.
20. Run `swift test` and package verification before considering a change complete.

Suggested prompt:

```text
Read docs/DEVELOPMENT.md first and follow every architecture/safety contract.
Keep asdf as source of truth, use typed AsdfService commands, preserve the single
mutation gate, bilingual UI, installed-first catalogs, AppNavigationModel deep links,
marker-owned shell integration/completions, project activity as UI-only metadata,
and guarded structured file writes. Runtime Storage is on-demand and may clean up only
through typed asdf uninstall; never delete runtime directories directly. Health repairs
must remain deterministic and per-issue. Preserve keyboard/VoiceOver semantics, add
tests, run swift test and package verification, and update this document when behavior
changes.
```
