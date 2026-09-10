# Development Guide

This is the architecture and safety handoff for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf. The asdf CLI and `.tool-versions` remain the sources of truth; the app is a typed UI/service layer over them.

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
- Do not persist copies of `.tool-versions`, plugin/runtime state, version catalogs, task logs, diagnostics, update responses, or shell-file contents.

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
                      -> AsdfService.setVersion (normal add/edit/reorder)
                      -> ToolVersionsMutationService (guarded delete-only exception)
          -> VersionsPolishedView
          -> Plugins
      -> feature windows
          -> Getting Started
          -> Set Runtime Version
          -> Plugin Manager
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
          -> .app + Info.plist + AppIcon.icns + localization resources
      -> scripts/create-dmg.sh
      -> scripts/notarize.sh (Developer ID mode only)
      -> .github/workflows/release.yml
```

## Core responsibilities

- `LocalizedAppRootView`: app-level setup/main-navigation gate and one-time Getting Started presentation.
- `AppModel`: shared application/project/runtime state and the application-wide mutation gate. Keep it `@MainActor`.
- `AsdfService`: typed asdf commands/parsers only.
- `AsdfCommandRunner`: process lifecycle, concurrent stdout/stderr draining, streaming, cancellation, complete result.
- `ProjectService`: project disk reads and `.tool-versions` parsing; no general-purpose writes.
- `ToolVersionsMutationService`: the narrowly-scoped delete-one-tool fallback because current asdf has no delete-entry command. It is not a generic text editor.
- `ProjectsPolishedView`: card-based project presentation; do not put variable-height multi-runtime content back inside macOS `List` rows.
- `ProjectToolVersionsManagerView`: visual management of a project's tool/version entries without exposing raw file editing.
- `VersionCatalog`: deterministic installed-first merge/order of installed/available/latest runtime versions.
- `VersionsPolishedView`: lazy per-plugin version browser. Installed versions remain at the beginning.
- `AppLanguage`: persisted English / Simplified Chinese preference and locale selection.
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

Do not create a second independent write lock. Feature-local writers use `AppModel.beginExternalWriteOperation()` and release it exactly once on every success/failure/cancellation path.

## asdf bootstrap contract

When no usable asdf executable is detected, show the dedicated setup UI instead of partially functional feature pages.

The installer must:

1. request `https://api.github.com/repos/asdf-vm/asdf/releases/latest` over HTTPS;
2. select the matching official macOS asset for the current app architecture (`darwin-arm64` or `darwin-amd64`);
3. require a valid GitHub asset `sha256:` digest;
4. download the archive and calculate SHA-256 locally with CryptoKit;
5. abort on a missing/malformed/mismatched digest;
6. extract with direct `/usr/bin/tar` invocation;
7. accept only a regular non-symlink `asdf` file;
8. run the staged binary with `asdf version` before installing it;
9. install to `~/.local/bin/asdf` without sudo/Homebrew;
10. persist/activate that exact executable through `AppModel.setExecutable`.

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
- explicit user selection is persisted in `UserDefaults` under `AppLanguage.storageKey`;
- language switching applies without app restart;
- all major scene roots receive `\.locale` derived from the selected `AppLanguage`;
- packaged builds copy `packaging/localizations/zh-Hans.lproj/Localizable.strings` into `Contents/Resources`;
- `packaging/Info.plist` declares `en` and `zh-Hans` in `CFBundleLocalizations`;
- runtime `String` values such as counts/statuses/messages must explicitly use the selected `AppLanguage` when literal-key localization cannot resolve them.

When adding visible UI:

1. use literal SwiftUI strings when possible;
2. add the Chinese key/value to `Localizable.strings`;
3. handle dynamic status/count/message strings in both languages;
4. keep package verification checking for `zh-Hans.lproj/Localizable.strings`.

Do not persist translated copies of asdf output; raw command output remains raw.

## Projects contract

### General project state

- Persist only managed project paths; reread `.tool-versions` from disk.
- Preserve ordered fallbacks and ignore comments when interpreting requirements.
- A requirement is satisfied if any configured fallback is usable.
- `system` and `path:*` are satisfied special values.
- Missing plugins show `Plugin missing`; lookup failures show `Unknown`.
- `Install Missing` never auto-installs plugins, installs sequentially, streams logs, supports cancellation, stops on first failure, and refreshes state after success.
- The main Projects UI remains card-based (`ScrollView` + `LazyVStack`).
- Project header/path/actions, requirement rows, fallback states, and install actions stay in stable visual regions that tolerate longer Chinese text.

### `.tool-versions` management

The Projects page includes a visual **Manage .tool-versions** workflow. Users never receive a raw editable text view for the whole file.

Normal writes must use asdf itself:

```text
asdf set <tool> <version> [<version>...]
```

The command runs with `currentDirectoryURL` set to the managed project folder. This covers:

- creating `.tool-versions` by adding the first tool;
- adding a tool entry;
- changing the primary version;
- adding/removing versions within a fallback chain;
- reordering a fallback chain.

Rules for add/edit/reorder:

- keep command construction inside `AsdfService` / AppModel project configuration APIs;
- validate tool and version arguments before running the command;
- version values must be individual asdf tokens (no whitespace);
- allow exact versions plus explicit special values such as `system`, `ref:*`, and `path:*`;
- selected fallback order is semantically significant and must be passed to `asdf set` unchanged;
- version catalog lookup is lazy per selected tool;
- catalog presentation is installed-first through `VersionCatalog.records`;
- refresh project snapshots and installed-version status after a successful write;
- all writes use the global mutation gate.

### Delete-one-tool exception

As of asdf 0.20, `asdf set` can create/update an entry but the CLI has no command to remove one tool entry from `.tool-versions`. Do **not** fake deletion by writing `system`, an empty version list, or an invented command.

`ToolVersionsMutationService` is the only permitted direct `.tool-versions` write and only for deleting one tool line after explicit confirmation.

Delete rules:

1. reread the current file immediately before mutation;
2. parse only the target tool line;
3. require exactly one matching tool entry;
4. compare its current ordered versions with the versions shown by the UI; if they changed, abort with `configurationChanged`;
5. if duplicate target-tool lines exist, abort rather than guess;
6. delete exactly the matched line range, including its own newline when present;
7. preserve every unrelated line, blank line, comment, and inline content outside that target line;
8. perform an atomic write and restore existing POSIX permissions when possible;
9. refresh project/runtime state after success;
10. never evolve this service into a general `.tool-versions` text rewrite API without an explicit architecture decision and tests.

Comments on the same line as the removed tool are intentionally removed with that tool line. Unrelated comments remain untouched.

## Versions contract

Read commands:

- `asdf list <tool>`;
- `asdf latest <tool>`;
- `asdf list all <tool>`.

The browser stays lazy; never query every plugin's full available catalog on app launch.

`VersionCatalog.records` ordering contract:

1. all locally installed versions, preserving their asdf-returned order;
2. remaining available versions, preserving upstream order;
3. latest version if absent from both lists;
4. no duplicates.

This installed-first ordering is intentional because catalogs may contain hundreds of versions. It also applies to version choices inside the project `.tool-versions` manager.

Writes:

- `asdf install <tool> <version>`;
- `asdf uninstall <tool> <version>`.

Uninstall always requires confirmation. `VersionUsageInspector` lists managed projects referencing the exact tool/version, including fallback entries. Runtime install/uninstall never rewrites project files.

## Version selection contract

- Project: `asdf set <tool> <version>` in the selected project directory.
- Home: `asdf set -u <tool> <version>`.

These writes use the same application-wide mutation gate as the project manager. The Set Runtime Version window currently writes one selected version or `system`; project mode replaces that tool's existing fallback chain and explains the impact before confirmation.

## Plugin management contract

Supported commands:

- `asdf plugin add <name> [<git-url>]`;
- `asdf plugin update <name> [<git-ref>]`;
- `asdf plugin update --all`;
- `asdf plugin remove <name>`.

Plugin mutations use the streaming/cancellable runner and global gate. Before removal, query installed versions and list every managed project that references the plugin. If impact lookup fails, do not offer blind destructive removal. Plugin removal never rewrites project files.

## Diagnostics contract

Supported diagnostics:

- `asdf info`;
- `asdf where <tool> [<version>]`;
- `asdf which <command>`;
- `asdf reshim <tool> <version>`.

`info`, `where`, and `which` are reads. `reshim` is a write and uses the global gate. Diagnostic output/reports are transient and copyable but not persisted.

## App update-check contract

The About window performs automatic-on-open and manual update checking.

Release-channel behavior:

- current builds may be GitHub prereleases because ad-hoc unsigned builds are intentionally prereleases;
- GitHub `/releases/latest` excludes prereleases, so update checking uses `GET /repos/syjsion/asdf-gui/releases` and resolves the newest non-draft semantic version itself;
- compare `vMAJOR.MINOR.PATCH` numerically, not lexicographically;
- include prereleases in version discovery;
- select `macos-arm64` DMG on Apple Silicon and `macos-x86_64` DMG on Intel;
- if no matching DMG exists, still offer the release page;
- update checking is read-only and unauthenticated;
- never auto-install or silently replace the running app.

`AppBuildInfo` reads `CFBundleShortVersionString` / `CFBundleVersion`; packaging injects release values.

## Persistence

Persisted small preferences:

- optional custom/GUI-installed asdf executable path;
- managed project paths;
- whether Getting Started was presented;
- selected app language.

Not persisted:

- `.tool-versions` contents;
- shell configuration contents or integration plans;
- plugin/runtime state;
- version catalogs;
- active task/bootstrap state/logs;
- removal-impact snapshots;
- diagnostics;
- update-check responses.

## Distribution contract

The project stays SwiftPM-based. Do not add an Xcode project solely for packaging unless a future capability genuinely requires it.

Bundle metadata:

- app name: `asdf GUI`;
- bundle identifier: `io.github.syjsion.asdf-gui`;
- minimum macOS: 14.0;
- non-App-Sandboxed;
- app icon generated by `scripts/generate-app-icon.py`;
- localizations: English + Simplified Chinese.

Release workflow modes:

- `adhoc`: no Apple credentials; prerelease DMGs; no notarization/Gatekeeper trust claim.
- `developer-id`: all required Apple credentials present; Developer ID signing + Hardened Runtime + timestamp + `notarytool` + stapling.

Partial Apple credentials fail closed. Both arm64 and x86_64 artifacts must succeed. `publish/vMAJOR.MINOR.PATCH` may be created from a tested `main` commit to trigger a release when a tag-writing tool is unavailable. See `docs/RELEASING.md`.

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
- [x] Card-based layout polish.
- [x] Visual `.tool-versions` management without raw text editing.
- [x] Add/edit/reorder through `asdf set`.
- [x] Guarded delete-one-tool fallback preserving unrelated content/comments/permissions.

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
- [x] tag/publish-branch release automation.
- [ ] smoke-test a downloaded ad-hoc prerelease on a real Mac.
- [ ] later smoke-test a notarized release.

### Phase 6 — Onboarding and product hardening
- [x] missing-asdf setup + verified asdf installer.
- [x] Shell Integration with guarded marker-scoped writes.
- [x] Getting Started guide.
- [x] English / Simplified Chinese in-app language switch.
- [x] About/version/update-check experience.
- [x] Projects layout repair.
- [x] Versions installed-first UX.
- [ ] Shell completion helper / more shells if deliberately designed.
- [ ] Project search/sort and broader macOS UI polish.

## Codex working agreement

When using Codex on this repository:

1. Read `docs/DEVELOPMENT.md`; for release changes also read `docs/RELEASING.md`.
2. Preserve SwiftUI/Foundation architecture unless explicitly changing it.
3. Keep normal asdf CLI construction/parsing in `AsdfService` and process handling in `AsdfCommandRunner`.
4. Keep project reads in `ProjectService`; do not introduce a generic project-file writer.
5. Put deterministic decisions in pure helpers and test them.
6. Reuse the global mutation gate for every new write/bootstrap/configuration workflow.
7. Reuse streaming/cancellation for potentially long commands.
8. Never expose a raw editable `.tool-versions` text editor as the normal management path.
9. For `.tool-versions` add/edit/reorder, use `asdf set` in the project directory.
10. Preserve `ToolVersionsMutationService` as a delete-one-tool-only exception; never use it for normal edits.
11. Deletion must keep the duplicate-entry check, target-version race check, unrelated-content preservation, atomic write, and permission preservation.
12. Never fake deletion by setting a tool to `system` or passing an empty version list.
13. Show known impact before destructive runtime/plugin removal.
14. Never auto-install plugins as a side effect of runtime installation.
15. Keep every version catalog lazy and installed-first, including project configuration UI.
16. Preserve the verified asdf bootstrap contract; no `curl | sh`, no skipped checksum verification.
17. Preserve Shell Integration preview/confirmation, marker-scoped edits, and race checks.
18. Keep localization resources and in-app language selection synchronized with new user-visible UI.
19. Dynamic visible strings must handle both English and Simplified Chinese where literal localization cannot resolve them.
20. App update checking includes prereleases and remains read-only; never silently update the app.
21. Preserve SwiftPM packaging, localization packaging, and both release architectures.
22. Never commit Apple credentials; preserve `adhoc` and `developer-id` modes and fail on partial credentials.
23. Never claim ad-hoc artifacts are notarized or Gatekeeper-trusted.
24. Update this document when architecture, localization, update-check, project mutation behavior, commands, persistence, safety, or distribution changes.
25. Run `swift test` and package verification before considering a change complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first; for release work also read docs/RELEASING.md.
Preserve the SwiftUI/Foundation architecture, global mutation gate, localization,
installed-first version catalogs, and distribution contracts. Normal .tool-versions
add/edit/reorder must run asdf set in the project directory. The only direct
.tool-versions mutation is ToolVersionsMutationService deleting exactly one tool
entry because asdf has no delete-entry command; preserve its race/duplicate/content/
permission safeguards. Add tests, run swift test and package verification, and update
this document when behavior or architecture changes.
```

## Design principles

- Explain state instead of exposing raw CLI buttons.
- Prefer project-centric workflows.
- Preserve asdf and `.tool-versions` as sources of truth.
- Prefer asdf's own commands for configuration writes whenever the CLI supports the operation.
- Make direct file mutations narrow, explicit, guarded, tested, and reversible where practical.
- Keep failure output visible and actionable.
- Make destructive effects explicit before execution.
- Favor native macOS layout behavior over web-style abstractions.
