# Development Guide

This is the architecture and safety handoff for future development, especially when using Codex.

## Product goal

`asdf-gui` is a native macOS SwiftUI application that makes common asdf workflows discoverable without replacing asdf. The asdf CLI and `.tool-versions` remain the sources of truth. The product should explain state and relationships instead of mirroring every CLI command as a button.

## Technical constraints

- macOS only; minimum macOS 14.
- Swift + SwiftUI + Foundation/AppKit where needed.
- No React, Electron, Tauri or WebView.
- Prefer Apple frameworks and zero third-party runtime dependencies.
- Normal asdf command construction/parsing belongs in `AsdfService`, never in SwiftUI views.
- Execute commands with `Process.executableURL` + argument arrays; no shell-string interpolation for normal operations.
- Only one mutation/bootstrap/configuration operation may run application-wide at a time.
- Destructive operations show known impact and require explicit confirmation.
- Keep distribution non-App-Sandboxed and outside the Mac App Store for now.
- Do not persist copies of `.tool-versions`, runtime/plugin catalogs, health reports, diagnostics, environment output, update responses or task logs.

## Architecture

```text
SwiftUI
  -> LocalizedAppRootView
      -> PolishedOverviewView / Project Health
      -> ProjectsPolishedView
          -> ProjectToolVersionsManagerView
      -> VersionsPolishedView
          -> RuntimeUpdateCenterView
      -> ResolutionView
          -> effective versions
          -> shim/command explorer
          -> EnvironmentInspectorSection
      -> Plugins / Plugin Manager / Discovery
      -> feature windows: Getting Started, Set Runtime Version,
         Diagnostics, Shell Integration, About, Settings

Shared state
  -> AppModel (@MainActor)
      -> AsdfService
          -> AsdfCommandRunner
      -> ProjectService
      -> ToolVersionsMutationService

Read-only feature models
  -> ResolutionModel
  -> EnvironmentInspectorModel
  -> RuntimeUpdateCenterModel
  -> ProjectHealthModel
  -> PluginDiscoveryModel
```

## Command runner contract

`AsdfCommandRunner.run` must invoke executables directly, drain stdout/stderr concurrently, support streamed output, wait for both streams to reach EOF, and terminate the underlying `Process` when the Swift task is cancelled. Output callbacks are chunks rather than guaranteed lines; UI updates from callbacks hop to MainActor.

## Global mutation gate

All writes share `AppModel.beginExternalWriteOperation()` / `endExternalWriteOperation()` or an existing AppModel task that participates in the same gate:

- in-app asdf installation;
- Shell Integration apply/remove;
- Project Install Missing;
- project `.tool-versions` add/edit/reorder;
- guarded delete-one-tool fallback;
- runtime Install / Uninstall;
- Project / Parent / Home `asdf set`;
- plugin Add / Update / Update All / Remove;
- Diagnostics `reshim`.

Do not add a second independent write lock.

## asdf bootstrap

When no usable asdf executable is detected, use the setup UI. The installer downloads the official macOS release asset, selects the current architecture, requires the GitHub SHA-256 digest, verifies it locally, extracts without shell piping, verifies the staged binary with `asdf version`, installs only to `~/.local/bin/asdf`, and persists that exact executable path. Never replace this with `curl | sh`, an unverified download or silent shell-rc changes.

## Shell Integration

Supported files:

- Zsh -> `~/.zshrc`
- Bash -> `~/.bash_profile`

Only the app-owned marker block may be added/replaced/removed. Always preview before writing, reject malformed/one-sided markers, reread before mutation to detect races, write atomically, preserve permissions when possible, and never silently add completions.

## Localization

Supported languages are English (`en`) and Simplified Chinese (`zh-Hans`). The preference is persisted under `AppLanguage.storageKey` and switching applies without restart. New visible UI must work in both languages. Prefer literal SwiftUI localization where the packaged table has the key; dynamic/new strings may use `AppLanguage.localized`, whose Simplified Chinese fallback map covers keys not yet consolidated into `Localizable.strings`.

Raw asdf output is never translated or persisted.

## Projects and `.tool-versions`

Persist only project paths and reread project configuration from disk. Preserve ordered fallbacks. A requirement is satisfied if any fallback is usable; `system` and `path:*` are satisfied special values. Missing plugins and lookup failures remain distinct states.

Normal writes use asdf itself:

```text
asdf set <tool> <version> [<version>...]
```

Run from the selected project directory. This covers first-file creation, add, edit and fallback reorder/removal. Version tokens must be validated and passed in the exact user-selected order.

### Delete-one-tool exception

Current asdf 0.20 has no CLI command to delete one tool entry. `ToolVersionsMutationService` is the only direct `.tool-versions` writer and only deletes one matching tool line after explicit confirmation. It must reread the file, require exactly one target entry, verify the ordered versions still match the UI snapshot, preserve unrelated content/comments, use atomic write, restore permissions when possible, and abort on duplicate/stale targets. Never evolve it into a general text editor.

## Version browser and updates

Read commands:

- `asdf list <tool>`
- `asdf list all <tool>`
- `asdf latest <tool>`

`VersionCatalog.records` remains installed-first: installed versions in asdf order, remaining available versions, then latest if absent, with no duplicates.

Runtime Install/Uninstall use exact versions. Uninstall shows managed-project usage impact first and never rewrites `.tool-versions`.

### Runtime Update Center

The Update Center is an on-demand read workflow. For each installed plugin it queries installed versions and `asdf latest`. An update is available only when the exact latest version is not locally installed.

Rules:

- never write `latest` into `.tool-versions`;
- install the resolved exact version through the existing runtime install task;
- never automatically uninstall old versions;
- never automatically switch Project/Parent/Home configuration after installation;
- refresh the row after a successful install;
- do not run this all-plugin scan during normal app startup.

## Version selection and inheritance

Supported scopes:

```text
Project: asdf set <tool> <version>
Parent:  asdf set -p <tool> <version>
Home:    asdf set -u <tool> <version>
```

Project and Parent commands run with the managed project as `currentDirectoryURL`. `ParentToolVersionsLocator` is preview-only: it finds the closest ancestor `.tool-versions` so the UI can show exactly which file `-p` is expected to update. If no parent file exists, disable/refuse Parent scope instead of relying on an opaque CLI failure. The actual write must still be performed by `asdf set -p`.

All three scopes write exact versions or explicit values such as `system`; do not persist moving aliases such as `latest`.

## Resolution, shims and environment

Read-only commands:

- `asdf current [tool]`
- `asdf which <command>` in a selected directory
- `asdf shimversions <command>`
- `asdf env <command>` in a selected directory

`Resolution` exists to answer why a project resolves a version/executable. `asdf current` parsing must preserve aligned columns, fallback strings and source paths containing spaces.

### Environment Inspector

`asdf env <command>` accepts a shimmed command, not an arbitrary shell program. The GUI must preserve that boundary; do not turn Environment Inspector into an unrestricted command runner.

The inspector compares the selected project context against Home using parsed `KEY=value` rows. Split on the first `=` only because values may contain `=`. Environment data is transient and never persisted. The project/Home comparison is user-triggered; do not scan environments on startup.

## Project Health

Project Health is also on demand. It combines project snapshots with `asdf current` per project.

Surface at least:

- unreadable project configuration;
- empty project configuration;
- missing plugin;
- missing runtime when no fallback is usable;
- unknown runtime lookup state;
- effective versions reported by `asdf current` as not installed;
- effective source `.tool-versions` paths, including parent/Home inheritance.

A satisfied fallback means the requirement is healthy even when earlier fallback entries are missing. Health reports are transient and should be sorted with higher-severity projects first. Normal startup only shows a cheap local summary and must not execute `asdf current` for every project.

## Plugins

Supported management commands:

- `asdf plugin add <name> [<git-url>]`
- `asdf plugin update <name> [<git-ref>]`
- `asdf plugin update --all`
- `asdf plugin remove <name>`
- `asdf plugin list all` for read-only discovery

Plugin discovery is lazy and searchable. Catalog install reuses the normal PluginManagementModel/global gate. Before plugin removal, list installed runtime versions and managed projects that reference the plugin. If impact lookup fails, do not offer blind removal.

## Diagnostics

Supported diagnostics are `asdf info`, `asdf where`, `asdf which` and `asdf reshim`. `info`/`where`/`which` are reads; `reshim` is a write using the global gate. Diagnostic output and reports are transient/copyable only.

Do not add unrestricted `asdf exec` merely for command coverage. A new CLI wrapper should provide a clear GUI workflow and reduce cognitive load.

## App updates

About uses the public GitHub Releases list rather than `/releases/latest` because current ad-hoc builds are prereleases. Compare semantic versions numerically, include prereleases, select the current architecture's DMG when available, and remain read-only. Never silently replace the running app.

## Persistence

Persisted small preferences:

- optional custom/GUI-installed asdf path;
- managed project paths;
- Getting Started presentation flag;
- selected app language.

Everything else is recomputed from asdf/files/GitHub when needed.

## Distribution

The project remains SwiftPM-based. Packaging uses `scripts/build-app.sh`, `scripts/create-dmg.sh`, optional `scripts/notarize.sh`, and `.github/workflows/release.yml`. Bundle ID is `io.github.syjsion.asdf-gui`, minimum macOS is 14, and the app is non-App-Sandboxed.

Release modes:

- `adhoc`: no Apple credentials, prerelease DMGs, no notarization/Gatekeeper trust claim;
- `developer-id`: all required credentials present, Developer ID + Hardened Runtime + timestamp + `notarytool` + stapling.

Partial credentials fail closed. Both arm64 and x86_64 artifacts must succeed. See `docs/RELEASING.md`.

## Roadmap status

Completed foundation now includes native SwiftUI architecture, project `.tool-versions` management, runtime version management, plugin management/discovery, diagnostics, packaging/releases, missing-asdf bootstrap, Shell Integration, bilingual UI, About/update check, project search/sort, Resolution/shim exploration, Environment Inspector, Parent (`set -p`) inheritance editing, Runtime Update Center and Project Health.

Still valuable future work:

- deliberate shell completion support / additional shells;
- structured `.asdfrc` settings editor if implemented without raw-text editing;
- richer Project Health remediation links/actions;
- UI/accessibility polish and real-Mac smoke testing;
- Developer ID/notarized release when credentials exist.

## Codex working agreement

When using Codex:

1. Read this file; for release work also read `docs/RELEASING.md`.
2. Preserve SwiftUI/Foundation architecture and the single global mutation gate.
3. Keep CLI construction/parsing in `AsdfService` and process lifecycle in `AsdfCommandRunner`.
4. Keep normal `.tool-versions` writes behind `asdf set`; preserve the delete-one-tool exception safeguards.
5. Keep version catalogs lazy and installed-first.
6. Parent scope must preview the nearest parent file but write through `asdf set -p`.
7. Update Center installs exact latest versions only; no automatic config rewrite or old-version deletion.
8. Environment Inspector only wraps shimmed-command `asdf env`; never expose arbitrary execution from it.
9. Project Health scans on demand and treats any usable fallback as satisfied.
10. Preserve English/Simplified Chinese behavior for new visible UI.
11. Do not weaken bootstrap checksum verification, shell-integration race protection, destructive confirmations or release-mode safety.
12. Add/update tests for parsers and non-UI decisions.
13. Update this document when commands, persistence, safety, architecture or distribution behavior changes.
14. Run `swift test` and package verification before considering a change complete.

Suggested prompt:

```text
Read docs/DEVELOPMENT.md first and follow every architecture/safety contract.
Keep asdf as source of truth, use typed AsdfService commands, preserve the single
mutation gate, bilingual UI, installed-first catalogs and guarded .tool-versions
writes. Add tests for parsers/decisions, run swift test and package verification,
and update this document when behavior changes.
```
