# Development Guide

This is the handoff/reference for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf. The asdf CLI and `.tool-versions` remain the sources of truth; the app is a typed UI/service layer over them.

## Technical constraints

- macOS only for now.
- Swift + SwiftUI + Foundation/AppKit where needed.
- Do not introduce React, Electron, Tauri, or WebView.
- Prefer Apple frameworks and zero third-party runtime dependencies.
- Keep CLI construction/parsing out of SwiftUI views.
- Execute asdf with `Process.executableURL` + argument arrays, never shell-string interpolation for normal commands.
- Destructive operations must show known impact and require explicit confirmation.
- Only one asdf write/bootstrap operation may run application-wide at a time.
- Distribution stays outside the Mac App Store and remains non-App-Sandboxed.
- Do not persist copies of `.tool-versions`, plugin/runtime state, version catalogs, task logs, or diagnostics.

## Architecture

```text
SwiftUI Views / feature windows
  -> RootContentView
      -> AsdfBootstrapModel
          -> AsdfInstaller
              -> official asdf GitHub latest release API
              -> SHA-256 asset verification
              -> ~/.local/bin/asdf
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
          -> .app + Info.plist + generated AppIcon.icns
          -> ad-hoc signature OR Developer ID signature
      -> scripts/create-dmg.sh
          -> compressed DMG + Applications shortcut
      -> scripts/notarize.sh
          -> Developer ID mode only
      -> .github/workflows/release.yml
          -> arm64 + x86_64 artifacts
          -> SHA256SUMS.txt
          -> GitHub Release / prerelease
```

## Core responsibilities

- `RootContentView`: application-level gate between setup and the normal navigation UI. Missing asdf should not expose partially functional feature pages.
- `AsdfBootstrapModel`: `@MainActor` feature state for in-app asdf installation, task log/cancellation, global write-gate participation, and activation of the installed executable through `AppModel.setExecutable`.
- `AsdfInstaller`: network/download/checksum/extraction/install primitive for official precompiled asdf releases. It never edits shell startup files.
- `AppModel`: shared app/project/runtime state and application-wide write-operation gate. Keep it `@MainActor`.
- `AppModel+VersionSelection`: short project/Home `asdf set` writes.
- `PluginManagementModel`: plugin task state, live logs, cancellation, removal-impact preparation.
- `DiagnosticsModel`: diagnostics state; `reshim` participates in the global write gate.
- `AsdfService`: the only place normal asdf argument arrays are constructed and parsed.
- `AsdfCommandRunner`: process lifecycle, stdout/stderr draining, streaming, cancellation, complete results.
- `ProjectService`: project disk access and `.tool-versions` reads.
- Pure helpers: deterministic planners/inspectors/report builders with unit tests.
- `scripts/build-app.sh`: single SwiftPM -> `.app` packaging path.
- `scripts/create-dmg.sh`: single DMG assembly path.
- `docs/RELEASING.md`: release runbook; update it whenever packaging/release behavior changes.

## Command runner contract

`AsdfCommandRunner.run` must:

- invoke an executable directly with argument arrays;
- concurrently drain stdout/stderr without pipe deadlocks;
- optionally stream output chunks;
- wait until both streams reach EOF before returning the final result;
- terminate the underlying `Process` when its Swift task is cancelled.

Output callbacks are chunks, not guaranteed lines. UI updates from callbacks must hop to `MainActor`.

## Global write-operation policy

These are writes/bootstrap operations and must share one application-wide gate:

- in-app asdf installation;
- Project `Install Missing`;
- Versions Install / Uninstall;
- project/Home `asdf set`;
- plugin Add / Update / Update All / Remove;
- Diagnostics `reshim`.

Do not create a second independent lock for new mutation workflows. The bootstrap feature acquires `AppModel.beginExternalWriteOperation()` before starting and releases it exactly once on every completion/cancellation/failure path.

## asdf bootstrap / missing-install contract

When no usable asdf executable is detected, `RootContentView` shows the setup experience instead of the normal Projects/Versions/Plugins UI.

The automatic installer follows the current official asdf precompiled-binary installation model:

1. request `https://api.github.com/repos/asdf-vm/asdf/releases/latest` over HTTPS;
2. use the current app architecture to select exactly one official macOS asset:
   - arm64 app -> `asdf-v<version>-darwin-arm64.tar.gz`;
   - x86_64 app -> `asdf-v<version>-darwin-amd64.tar.gz`;
3. require the GitHub release asset `digest` field to contain a valid `sha256:<64 hex chars>` value;
4. download the archive from the asset's `browser_download_url`;
5. calculate SHA-256 locally with CryptoKit and stop on any mismatch or missing digest;
6. extract with direct `/usr/bin/tar` invocation into a temporary directory;
7. accept only a regular, non-symlink file named `asdf` from the archive;
8. stage it under `~/.local/bin`, set executable permissions, and run `asdf version` before replacing/creating the final target;
9. install to `~/.local/bin/asdf` with no `sudo` and no Homebrew dependency;
10. activate/persist that exact executable through `AppModel.setExecutable` and refresh normal app state.

Rules:

- Never replace this flow with `curl | sh`, shell-string execution, or an unverified download.
- Never continue automatic installation if the expected SHA-256 digest is absent or malformed.
- Do not automatically edit `~/.zshrc`, `~/.bashrc`, Fish config, or any other shell startup file. Shell integration is a separate explicit user decision.
- The GUI-managed binary path does not need to be on Finder's inherited `PATH` because the app persists and invokes the absolute path.
- Installing the asdf core does not imply every plugin dependency is installed. Plugin-specific dependencies remain the responsibility of each plugin and should surface through normal task errors.
- Existing asdf installations remain supported through automatic path detection or Settings -> Choose asdf.
- Keep release/version lookup dynamic; do not hardcode one asdf version into the installer.

## Projects contract

- Persist only known project paths; reread configuration from disk.
- Preserve ordered `.tool-versions` fallbacks and ignore comments.
- A requirement is satisfied when any fallback is usable.
- `system` and `path:*` are satisfied special values.
- Missing plugins show `Plugin missing`; lookup failures show `Unknown`.
- `Install Missing` never auto-installs plugins, installs sequentially, stops on first failure, supports cancellation, streams logs, and refreshes state after success.

## Versions contract

Read commands:

- `asdf list <tool>`;
- `asdf latest <tool>`;
- `asdf list all <tool>`.

The Versions browser stays lazy: do not query every plugin's full available-version list on launch.

Writes:

- `asdf install <tool> <version>`;
- `asdf uninstall <tool> <version>`.

Uninstall always requires confirmation. `VersionUsageInspector` shows managed projects that explicitly reference the selected tool/version, including fallback entries. Runtime install/uninstall never rewrites `.tool-versions`.

## Version selection contract

- Project: `asdf set <tool> <version>` in the selected project directory.
- Home: `asdf set -u <tool> <version>`.

The UI currently writes one exact installed version or `system`, not `latest`. Project mode replaces the selected tool's fallback chain with the selected single value and must explain that before confirmation.

## Plugin management contract

Supported commands:

- `asdf plugin add <name> [<git-url>]`;
- `asdf plugin update <name> [<git-ref>]`;
- `asdf plugin update --all`;
- `asdf plugin remove <name>`.

Plugin mutations use the streaming/cancellable runner and global write gate. Before removal, query installed versions and list every managed project that references the plugin. If impact lookup fails, do not offer a blind removal path. Plugin removal does not rewrite project files.

## Diagnostics contract

Supported diagnostics:

- `asdf info`;
- `asdf where <tool> [<version>]`;
- `asdf which <command>`;
- `asdf reshim <tool> <version>`.

`info`, `where`, and `which` are reads. `reshim` is a write. Diagnostic output/reports are transient and copyable but not persisted.

## Persistence

Persisted in `UserDefaults`:

- optional custom/GUI-installed asdf executable path;
- managed project paths.

Not persisted:

- `.tool-versions` contents;
- plugin/runtime state;
- version catalogs;
- active task/bootstrap state/logs;
- removal-impact snapshots;
- diagnostics.

If App Sandbox is introduced later, managed project paths must migrate to security-scoped bookmarks first.

## Distribution contract

The project deliberately stays SwiftPM-based. Do not add an Xcode project solely for packaging unless a future capability genuinely requires it.

Bundle metadata:

- app name: `asdf GUI`;
- bundle identifier: `io.github.syjsion.asdf-gui`;
- minimum macOS: 14.0;
- non-App-Sandboxed;
- App Icon generated by `scripts/generate-app-icon.py`.

### Release signing modes

The Release workflow has two supported modes.

#### `adhoc`

Used automatically when **none** of the six Apple signing/notarization secrets are configured.

- app is ad-hoc signed with Hardened Runtime;
- no Apple notarization is attempted;
- Gatekeeper trust is not asserted;
- DMG filenames include `adhoc`;
- GitHub Release is marked `prerelease`;
- release notes must tell users to Control-click/right-click the app and choose Open on first launch.

Ad-hoc publishing is a supported project mode while no paid Apple Developer account exists. Never describe these artifacts as Apple-signed or notarized.

#### `developer-id`

Used automatically only when **all six** Apple secrets are configured.

- Developer ID Application signing;
- Hardened Runtime + secure timestamp;
- app and DMG notarization with `notarytool`;
- stapling and Gatekeeper verification;
- normal GitHub Release.

If only some secrets exist, the workflow must fail rather than silently downgrade.

### Release triggers

Supported release triggers:

- tag: `vMAJOR.MINOR.PATCH`;
- publish branch: `publish/vMAJOR.MINOR.PATCH`.

The publish-branch trigger exists for automation that can create branches but cannot directly create tags. `gh release create --target` creates the release tag at the workflow commit when needed.

Release artifacts are architecture-specific and both must succeed:

```text
asdf-gui-X.Y.Z-macos-arm64-<mode>.dmg
asdf-gui-X.Y.Z-macos-x86_64-<mode>.dmg
SHA256SUMS.txt
```

See `docs/RELEASING.md` for the operational procedure and first-launch behavior.

## Current implementation / roadmap

### Phase 1 — Foundation

- [x] Native SwiftUI navigation.
- [x] Typed Process runner/service boundary.
- [x] asdf detection, version, plugins.
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

- [x] Reproducible SwiftPM app bundle.
- [x] App icon / Info.plist metadata.
- [x] DMG packaging and verification.
- [x] arm64 + x86_64 release artifacts.
- [x] Ad-hoc GitHub prerelease mode without Apple credentials.
- [x] Optional Developer ID + notarization mode when credentials become available.
- [x] Tag and publish-branch release automation with checksums.
- [ ] Smoke-test the first published ad-hoc prerelease on a real Mac downloaded from GitHub.
- [ ] Later: configure Apple credentials and smoke-test the first notarized release.

### Phase 6 — Onboarding and product hardening

- [x] Dedicated missing-asdf setup state.
- [x] Verified one-click installation of the latest official precompiled asdf binary.
- [x] Automatic architecture selection and SHA-256 validation.
- [x] Persist/activate the GUI-installed executable without depending on shell PATH.
- [ ] Explicit optional terminal shell-integration helper with preview/confirmation.
- [ ] First-run guidance after asdf is ready (plugin/project next actions).
- [ ] About/version/update-check experience.
- [ ] Project search/sort and broader macOS UI polish.

## Current asdf command/install assumptions

Verify official asdf docs before changing command or bootstrap behavior:

- package-manager install on macOS: `brew install asdf`;
- official precompiled binary installation: download the matching release archive and place the `asdf` binary on PATH;
- `asdf plugin add <name> [<git-url>]`;
- `asdf plugin update <name> [<git-ref>]` / `asdf plugin update --all`;
- `asdf plugin remove <name>`;
- `asdf list <tool>`, `asdf list all <tool>`, `asdf latest <tool>`;
- `asdf install <tool> <version>`, `asdf uninstall <tool> <version>`;
- `asdf set [-u] <tool> <versions...>`;
- `asdf where <tool> [<version>]`;
- `asdf which <command>`;
- `asdf reshim <tool> <version>`;
- `asdf info`.

`.tool-versions` may contain ordered fallbacks, `system`, `ref:*`, and `path:*`. Current UI does not write `latest`.

## Codex working agreement

When using Codex on this repository:

1. Read `docs/DEVELOPMENT.md` and, for distribution work, `docs/RELEASING.md` first.
2. Preserve the SwiftUI/Foundation architecture unless explicitly changing it.
3. Keep CLI construction/parsing in `AsdfService` and process handling in `AsdfCommandRunner`.
4. Keep project disk access in `ProjectService` or a dedicated file service.
5. Put deterministic decisions in pure helpers and test them.
6. Reuse the global write gate for every new asdf mutation/bootstrap workflow.
7. Reuse streaming/cancellation for potentially long commands.
8. Never silently mutate `.tool-versions`.
9. Show known impact before destructive runtime/plugin removal.
10. Never auto-install plugins as a side effect of runtime installation.
11. Keep the Versions browser lazy.
12. Preserve the verified bootstrap contract: official release API, exact architecture asset, SHA-256 verification, no `curl | sh`, no silent shell-rc edits.
13. Do not persist CLI-derived caches/logs without a documented design change.
14. Preserve the SwiftPM packaging path and update packaging scripts/docs together.
15. Never commit Apple certificates, keys, passwords, or notarization credentials.
16. Preserve both release modes: `adhoc` with no secrets, `developer-id` only with all secrets. Partial credentials must fail closed.
17. Never claim ad-hoc artifacts are notarized or Gatekeeper-trusted.
18. Keep both arm64 and x86_64 release outputs unless support policy is deliberately changed and documented.
19. Update this document when architecture, bootstrap, command, persistence, task, safety, or distribution behavior changes.
20. Run `swift test` and package verification before considering changes complete.

Suggested Codex prompt:

```text
Read docs/DEVELOPMENT.md first; for packaging/release work also read docs/RELEASING.md.
Follow the documented architecture, bootstrap verification, safety, write-gate, and
distribution contracts. Keep asdf CLI construction in AsdfService, process execution
in AsdfCommandRunner, and project disk access in ProjectService. Preserve destructive-
action impact checks. Never replace the asdf bootstrap with curl|sh, skip SHA-256
verification, or silently edit shell startup files. For release changes preserve both
adhoc and developer-id modes, keep both architectures, run swift test and package
verification, and update docs whenever behavior changes.
```

## Design principles

- Explain state instead of exposing raw CLI buttons.
- Prefer project-centric workflows.
- Preserve asdf and `.tool-versions` as sources of truth.
- Make first-run setup safe and understandable rather than assuming CLI prerequisites.
- Keep failure output visible and actionable.
- Make destructive/expensive behavior explicit.
- Keep packaging reproducible.
- Be precise about trust: ad-hoc is not notarized; Developer ID mode is.
