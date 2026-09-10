# Development Guide

This is the architecture and safety handoff for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf. The asdf CLI and `.tool-versions` remain the sources of truth; the app is a typed UI/service layer over them.

## Technical constraints

- macOS only for now.
- Swift + SwiftUI + Foundation/AppKit where needed.
- Do not introduce React, Electron, Tauri, or WebView.
- Prefer Apple frameworks and zero third-party runtime dependencies.
- Keep asdf CLI construction/parsing out of SwiftUI views.
- Execute normal asdf operations with `Process.executableURL` + argument arrays; do not interpolate shell command strings.
- Destructive operations must show known impact and require explicit confirmation.
- Only one mutation/bootstrap/configuration operation may run application-wide at a time.
- Distribution stays outside the Mac App Store and remains non-App-Sandboxed.
- Do not persist copies of `.tool-versions`, plugin/runtime state, version catalogs, task logs, diagnostics, or shell-file contents.

## Architecture

```text
SwiftUI Views / feature windows
  -> OnboardingRootView
      -> RootContentView
          -> AsdfBootstrapModel
              -> AsdfInstaller
                  -> official asdf GitHub latest release API
                  -> SHA-256 verification
                  -> ~/.local/bin/asdf
          -> AppModel + feature models
              -> AsdfService
                  -> AsdfCommandRunner
                      -> Foundation.Process + Pipe
              -> ProjectService
                  -> ToolVersionsParser
                  -> RequirementStatusResolver
                  -> ProjectInstallPlanner
              -> VersionCatalog / VersionUsageInspector
              -> PluginRemovalInspector
              -> DiagnosticReportBuilder
          -> ShellIntegrationModel
              -> ShellIntegrationService
                  -> ~/.zshrc or ~/.bash_profile

Distribution
  -> SwiftPM release executable
      -> scripts/build-app.sh
      -> scripts/create-dmg.sh
      -> scripts/notarize.sh (Developer ID mode only)
      -> .github/workflows/release.yml
          -> arm64 + x86_64 artifacts
          -> SHA256SUMS.txt
          -> GitHub Release / prerelease
```

## Core responsibilities

- `OnboardingRootView`: presents the one-time Getting Started window for a fresh asdf installation with no plugins/projects. It must not block access to the normal app after presentation.
- `RootContentView`: gates the normal navigation UI behind a usable asdf executable. Missing asdf shows setup instead of partially functional feature pages.
- `AsdfBootstrapModel`: `@MainActor` installer state/log/cancellation and activation of the installed executable.
- `AsdfInstaller`: verified network/download/checksum/extraction/install primitive for official precompiled asdf releases.
- `AppModel`: shared application/project/runtime state plus the application-wide external write gate. Keep it `@MainActor`.
- `AsdfService`: typed asdf commands and parsers. Views never assemble normal asdf CLI arguments.
- `AsdfCommandRunner`: process lifecycle, concurrent stdout/stderr draining, streaming, cancellation, and complete results.
- `ProjectService`: project disk reads; it does not directly mutate `.tool-versions`.
- `ShellIntegrationModel`: UI-facing shell integration state. Shell-file writes must acquire/release the existing `AppModel` external write gate.
- `ShellIntegrationService`: deterministic planning plus guarded apply/remove for the app-owned shell block only.
- Pure helpers/planners/inspectors/report builders: deterministic logic with unit tests.
- `scripts/build-app.sh`, `scripts/create-dmg.sh`, `scripts/notarize.sh`: the only packaging/release command paths.
- `docs/RELEASING.md`: operational release runbook; keep it synchronized with workflow/scripts.

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

When no usable asdf executable is detected, show the dedicated setup UI.

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

Never replace this with `curl | sh`, an unverified download, or silent shell-rc modification. Keep release lookup dynamic rather than pinning one asdf version in source.

## Shell Integration contract

Current official asdf 0.20.x setup requires the shims directory on PATH. On macOS the documented files are:

- Zsh: `~/.zshrc`;
- Bash: `~/.bash_profile`.

asdf GUI supports those two shells through an explicit **Shell Integration** window. It must never silently edit an rc file.

The managed block is marker-delimited:

```sh
# >>> asdf GUI shell integration >>>
export PATH='<active-asdf-directory>':"$PATH"
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
# <<< asdf GUI shell integration <<<
```

Rules:

- Preview the exact block and target file before writing.
- Add the directory of the exact executable currently used by the GUI so Terminal resolves the same asdf installation.
- Add `${ASDF_DATA_DIR:-$HOME/.asdf}/shims` ahead of PATH for runtime shims.
- Zsh targets `.zshrc`; Bash targets `.bash_profile`.
- Never modify text outside the two asdf GUI markers.
- If both markers are absent, append one block; never append duplicate managed blocks.
- If both markers exist but the active executable changes, replace only the managed block and report `needsUpdate`.
- If only one marker exists or marker order is malformed, refuse to write until the user fixes the file.
- Planning captures the original file contents. Apply/remove must reread the file and fail with `configurationChanged` if another process/user edited it after preview generation.
- Preserve existing POSIX permissions after an atomic write when possible.
- Remove Integration deletes only the app-owned block.
- Do not add shell completions automatically. Completion setup may be a future separate explicit feature.
- Fish/Nushell/POSIX-shell support is not implemented yet; do not guess their syntax from Zsh/Bash.

## First-run guidance contract

A fresh profile that has a usable asdf executable but no plugins and no managed projects gets the Getting Started window once. Presentation state may be persisted as a small UI preference; the underlying asdf/plugin/project state remains authoritative and uncached.

The guide should explain the sequence rather than execute hidden work:

1. asdf ready;
2. optional Shell Integration;
3. add a plugin;
4. install a runtime from Versions;
5. add a project containing `.tool-versions`.

Plugin/runtime/project installation remains user-triggered. The guide is always reopenable from the app menu.

## Projects contract

- Persist only managed project paths; reread `.tool-versions` from disk.
- Preserve ordered fallbacks and ignore comments.
- A requirement is satisfied if any configured fallback is usable.
- `system` and `path:*` are satisfied special values.
- Missing plugins show `Plugin missing`; lookup failures show `Unknown`.
- `Install Missing` never auto-installs plugins, installs sequentially, streams logs, supports cancellation, stops on first failure, and refreshes state after success.

## Versions contract

Read commands:

- `asdf list <tool>`;
- `asdf latest <tool>`;
- `asdf list all <tool>`.

The Versions browser stays lazy; never query all plugins' available-version catalogs on app launch.

Writes:

- `asdf install <tool> <version>`;
- `asdf uninstall <tool> <version>`.

Uninstall always requires confirmation. `VersionUsageInspector` lists managed projects that explicitly reference the selected tool/version, including fallback entries. Runtime install/uninstall never rewrites project files.

## Version selection contract

- Project: `asdf set <tool> <version>` in the selected project directory.
- Home: `asdf set -u <tool> <version>`.

The UI currently writes one exact installed version or `system`, not `latest`. Project mode replaces that tool's existing fallback chain and must explain the impact before confirmation.

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

## Persistence

Persisted small preferences:

- optional custom/GUI-installed asdf executable path;
- managed project paths;
- whether the one-time Getting Started window has already been presented.

Not persisted:

- `.tool-versions` contents;
- shell configuration contents or integration plans;
- plugin/runtime state;
- version catalogs;
- active task/bootstrap state/logs;
- removal-impact snapshots;
- diagnostics.

If App Sandbox support is introduced later, managed project paths must migrate to security-scoped bookmarks first.

## Distribution contract

The project stays SwiftPM-based. Do not add an Xcode project solely for packaging unless a future capability genuinely requires it.

Bundle metadata:

- app name: `asdf GUI`;
- bundle identifier: `io.github.syjsion.asdf-gui`;
- minimum macOS: 14.0;
- non-App-Sandboxed;
- app icon generated by `scripts/generate-app-icon.py`.

Release workflow supports two modes:

- `adhoc`: used when none of the Apple signing/notarization secrets exist; publishes clearly named prerelease DMGs without claiming notarization/Gatekeeper trust.
- `developer-id`: used only when all required Apple secrets exist; Developer ID signing, Hardened Runtime, timestamp, `notarytool`, stapling, Gatekeeper verification.

Partial Apple credentials must fail closed. Both arm64 and x86_64 artifacts must succeed. See `docs/RELEASING.md` for details.

## Roadmap

### Phase 1 — Foundation

- [x] Native SwiftUI navigation.
- [x] Typed Process/service boundary.
- [x] asdf detection/version/plugins.
- [x] Manual executable selection/persistence.
- [x] Streaming output and cancellation.

### Phase 2 — Projects

- [x] Add/remove project folders.
- [x] Parse `.tool-versions` and fallbacks.
- [x] Required vs installed state.
- [x] Install Missing with logs/cancel.

### Phase 3 — Version management

- [x] Installed/latest/available queries.
- [x] Versions browser/search/filter.
- [x] Runtime Install/Uninstall.
- [x] Uninstall project-usage impact.
- [x] Project/Home `asdf set`.

### Phase 4 — Plugins and diagnostics

- [x] Plugin Add / Update / Update All / Remove.
- [x] Plugin-removal impact/confirmation.
- [x] `where`, `which`, `reshim`, `info`.
- [x] Copyable diagnostic report.

### Phase 5 — Distribution

- [x] Reproducible SwiftPM app bundle and DMG.
- [x] arm64 + x86_64 artifacts and checksums.
- [x] Ad-hoc GitHub prerelease mode without Apple credentials.
- [x] Optional Developer ID/notarization mode.
- [x] Tag and publish-branch release automation.
- [ ] Smoke-test a downloaded ad-hoc prerelease on a real Mac.
- [ ] Later configure Apple credentials and smoke-test a notarized release.

### Phase 6 — Onboarding and product hardening

- [x] Dedicated missing-asdf setup state.
- [x] Verified one-click latest official asdf binary install.
- [x] Architecture selection + SHA-256 verification.
- [x] Persist/activate GUI-installed executable independent of Finder PATH.
- [x] Explicit Zsh/Bash Shell Integration with preview/confirmation/update/remove.
- [x] First-run Getting Started guidance.
- [ ] Shell completion helper and additional shells if deliberately designed.
- [ ] About/version/update-check experience.
- [ ] Project search/sort and broader macOS UI polish.

## Current asdf assumptions

Verify current official asdf docs before changing related behavior. Current assumptions include:

- macOS package-manager install: `brew install asdf`;
- official precompiled binary release assets are available for Darwin architectures;
- required shims PATH for Zsh: add `export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"` to `~/.zshrc`;
- required shims PATH for Bash on macOS: same export in `~/.bash_profile`;
- normal plugin/version/set/where/which/reshim/info commands documented elsewhere in this file remain typed through `AsdfService`.

`.tool-versions` may contain ordered fallbacks, `system`, `ref:*`, and `path:*`. Current UI does not write `latest`.

## Codex working agreement

When using Codex on this repository:

1. Read `docs/DEVELOPMENT.md` and, for distribution changes, `docs/RELEASING.md` first.
2. Preserve the SwiftUI/Foundation architecture unless explicitly changing it.
3. Keep normal asdf CLI construction/parsing in `AsdfService` and process handling in `AsdfCommandRunner`.
4. Keep project disk access in `ProjectService` or a dedicated file service.
5. Put deterministic decisions in pure helpers and test them.
6. Reuse the global mutation gate for every new write/bootstrap/configuration workflow.
7. Reuse streaming/cancellation for potentially long commands.
8. Never silently mutate `.tool-versions`.
9. Show known impact before destructive runtime/plugin removal.
10. Never auto-install plugins as a side effect of runtime installation.
11. Keep the Versions browser lazy.
12. Preserve the verified bootstrap contract: official release API, exact architecture asset, SHA-256 verification, no `curl | sh`.
13. Preserve the Shell Integration contract: explicit preview/confirmation, marker-scoped edits only, configuration-race check, no silent rc edits, no guessed unsupported-shell syntax.
14. Do not persist shell-file contents, CLI-derived caches, or task logs without a documented design change.
15. Preserve the SwiftPM packaging path and both release architectures.
16. Never commit Apple credentials; preserve `adhoc` and `developer-id` release modes and fail on partial credentials.
17. Never claim ad-hoc artifacts are notarized or Gatekeeper-trusted.
18. Update this document when architecture, bootstrap, shell integration, commands, persistence, safety, task policy, or distribution behavior changes.
19. Run `swift test` and package verification before considering changes complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first; for release work also read docs/RELEASING.md.
Follow the architecture, bootstrap verification, shell-integration, safety, global
mutation-gate, and distribution contracts. Keep normal asdf CLI construction in
AsdfService, process execution in AsdfCommandRunner, and project disk access in
ProjectService. Never replace bootstrap with curl|sh, skip SHA-256 verification,
silently edit shell files, or change text outside the asdf GUI shell markers.
Add/update tests, run swift test and package verification, and update this document
when behavior or architecture changes.
```

## Design principles

- Explain state instead of exposing raw CLI buttons.
- Prefer project-centric workflows.
- Preserve asdf and `.tool-versions` as sources of truth.
- Make shell/file mutations explicit and reversible where possible.
- Keep failure output visible and actionable.
- Make destructive/expensive behavior explicit.
- Keep packaging reproducible.
- Be precise about release trust: ad-hoc is not notarized; Developer ID mode is.
