# Development Guide

This is the architecture/safety handoff for future development, especially when using Codex.

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
- Do not persist copies of `.tool-versions`, plugin/runtime state, version catalogs, task logs, diagnostics, or shell-file contents.

## Current architecture

```text
SwiftUI scenes
  -> LocalizedAppRootView
      -> missing-asdf setup / AsdfBootstrapModel
      -> main NavigationSplitView
          -> Overview
          -> ProjectsPolishedView
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

- `LocalizedAppRootView`: application-level setup/main-navigation gate and one-time Getting Started presentation.
- `AppModel`: shared application/project/runtime state and the application-wide mutation gate. Keep it `@MainActor`.
- `AsdfService`: typed asdf commands/parsers only.
- `AsdfCommandRunner`: process lifecycle, concurrent stdout/stderr draining, streaming, cancellation, complete result.
- `ProjectService`: project disk reads; never silently rewrites `.tool-versions`.
- `ProjectsPolishedView`: card-based project presentation; avoid nesting variable-height multi-line runtime content inside a macOS `List` row.
- `VersionCatalog`: deterministic merge/order of installed/available/latest runtime versions.
- `VersionsPolishedView`: lazy per-plugin version browser. Installed versions must remain at the beginning of the list.
- `AppLanguage`: persisted English / Simplified Chinese preference and locale selection.
- `AppUpdateChecker`: public GitHub Release lookup; no authentication or repository mutation.
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
- Versions Install / Uninstall;
- project/Home `asdf set`;
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
- language switching must apply without app restart;
- all major scene roots receive `\.locale` derived from the selected `AppLanguage`;
- packaged builds copy `packaging/localizations/zh-Hans.lproj/Localizable.strings` into `Contents/Resources`;
- `packaging/Info.plist` declares `en` and `zh-Hans` in `CFBundleLocalizations`;
- dynamic strings that originate as runtime `String` values (counts/statuses/messages) cannot rely on literal-key localization and should explicitly use the selected `AppLanguage` or construct language-specific text.

When adding visible UI:

1. use literal SwiftUI strings when possible so localization tables can resolve them;
2. add the Chinese key/value to `Localizable.strings`;
3. for dynamic status/count/message strings, handle both languages explicitly;
4. package verification must continue checking that `zh-Hans.lproj/Localizable.strings` exists in the `.app`.

Do not persist translated copies of asdf output; raw command output remains raw.

## Projects contract

- Persist only managed project paths; reread `.tool-versions` from disk.
- Preserve ordered fallbacks and ignore comments.
- A requirement is satisfied if any configured fallback is usable.
- `system` and `path:*` are satisfied special values.
- Missing plugins show `Plugin missing`; lookup failures show `Unknown`.
- `Install Missing` never auto-installs plugins, installs sequentially, streams logs, supports cancellation, stops on first failure, and refreshes state after success.
- The main Projects UI is card-based (`ScrollView` + `LazyVStack`). Do not revert to variable-height multi-runtime content embedded directly in a macOS `List` row; that layout caused visual row/spacing corruption.
- Project header/path/actions, requirement rows, fallback states, and install actions should stay in stable visual regions that tolerate longer Chinese text.

## Versions contract

Read commands:

- `asdf list <tool>`;
- `asdf latest <tool>`;
- `asdf list all <tool>`.

The browser stays lazy; never query every plugin's full available catalog on app launch.

`VersionCatalog.records` ordering contract:

1. all locally installed versions, preserving their asdf-returned order;
2. remaining available versions, preserving upstream order;
3. latest version if it was absent from both lists;
4. no duplicates.

This installed-first ordering is intentional because plugin catalogs may contain hundreds of versions. Do not regress to available-first ordering.

Writes:

- `asdf install <tool> <version>`;
- `asdf uninstall <tool> <version>`.

Uninstall always requires confirmation. `VersionUsageInspector` lists managed projects referencing the exact tool/version, including fallback entries. Runtime install/uninstall never rewrites project files.

## Version selection contract

- Project: `asdf set <tool> <version>` in the selected project directory.
- Home: `asdf set -u <tool> <version>`.

The UI writes one exact installed version or `system`, not `latest`. Project mode replaces that tool's existing fallback chain and must explain the impact before confirmation.

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

The About window provides manual/automatic-on-open update checking.

Important release-channel behavior:

- current project releases may be GitHub prereleases because ad-hoc unsigned builds are intentionally published as prereleases;
- GitHub `/releases/latest` excludes prereleases, so app update checking must use `GET /repos/syjsion/asdf-gui/releases` and resolve the newest non-draft semantic version itself;
- compare `vMAJOR.MINOR.PATCH` numerically, not lexicographically;
- include prereleases in version discovery;
- when multiple releases have the same semantic version, prefer the stable release when deliberately implemented;
- select a `.dmg` whose filename contains `macos-arm64` on Apple Silicon or `macos-x86_64` on Intel;
- if no matching DMG exists, still offer the GitHub release page;
- update checking is read-only and uses the public GitHub API without credentials;
- do not auto-install or silently replace the running app. The UI only opens the matching DMG/release URL.

`AppBuildInfo` reads `CFBundleShortVersionString` / `CFBundleVersion`; packaging injects the release version/build number.

## Persistence

Persisted small preferences:

- optional custom/GUI-installed asdf executable path;
- managed project paths;
- whether the one-time Getting Started window was presented;
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

Partial Apple credentials must fail closed. Both arm64 and x86_64 artifacts must succeed. See `docs/RELEASING.md`.

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
- [x] Card-based layout polish for variable-height project/runtime content.

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
4. Keep project disk access in `ProjectService` or a dedicated file service.
5. Put deterministic decisions in pure helpers and test them.
6. Reuse the global mutation gate for every new write/bootstrap/configuration workflow.
7. Reuse streaming/cancellation for potentially long commands.
8. Never silently mutate `.tool-versions`.
9. Show known impact before destructive runtime/plugin removal.
10. Never auto-install plugins as a side effect of runtime installation.
11. Keep the Versions browser lazy and installed-first.
12. Preserve the verified asdf bootstrap contract; no `curl | sh`, no skipped checksum verification.
13. Preserve the Shell Integration contract; explicit preview/confirmation, marker-scoped edits only, race check, no guessed shell syntax.
14. Keep localization resources and in-app language selection in sync with new user-visible UI.
15. Dynamic visible strings must handle both English and Simplified Chinese when literal localization cannot resolve them.
16. App update checking must include prereleases and remain read-only; never silently update the app.
17. Preserve the SwiftPM packaging path, localization packaging, and both release architectures.
18. Never commit Apple credentials; preserve `adhoc` and `developer-id` modes and fail on partial credentials.
19. Never claim ad-hoc artifacts are notarized or Gatekeeper-trusted.
20. Update this document when architecture, localization, update-check, bootstrap, commands, persistence, safety, task policy, or distribution behavior changes.
21. Run `swift test` and package verification before considering a change complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first; for release work also read docs/RELEASING.md.
Follow the architecture, localization, update-check, bootstrap verification,
shell-integration, safety, global mutation-gate, and distribution contracts.
Keep normal asdf CLI construction in AsdfService, process execution in
AsdfCommandRunner, and project disk access in ProjectService. Keep Versions lazy and
installed-first, preserve card-based Projects layout, localize new visible UI in both
English and Simplified Chinese, add/update tests, run swift test and package
verification, and update this document when behavior or architecture changes.
```

## Design principles

- Explain state instead of exposing raw CLI buttons.
- Prefer project-centric workflows.
- Preserve asdf and `.tool-versions` as sources of truth.
- Make shell/file mutations explicit and reversible where possible.
- Keep failure output visible and actionable.
- Treat localization as a product contract, not a one-off translation pass.
- Keep installed/local state easy to find before large remote catalogs.
- Keep update checking transparent and user-triggered for installation.
- Keep packaging reproducible and trust claims precise.
