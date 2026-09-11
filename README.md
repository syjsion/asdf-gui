# asdf GUI

Native macOS GUI for [asdf](https://asdf-vm.com/), built with SwiftUI and Foundation.

The project keeps asdf, `.tool-versions`, and machine-level `.asdfrc` settings as the sources of truth. The app is a typed, visual control and explanation layer over the existing CLI rather than a reimplementation of version management.

## Requirements

- macOS 14+
- asdf may already be installed, or asdf GUI can install the latest official macOS binary for you
- Xcode / a compatible Swift toolchain is only required when building from source

## Highlights

### Overview and daily use

- **Quick Access** surfaces up to four favorite projects plus recently used non-favorites directly on the Overview page.
- Quick Access can deep-link into Projects or open the structured `.tool-versions` manager without making users search for the project again.
- Project activity is reread from persisted preferences when Overview becomes active, so Favorites/Recent changes made in Projects remain consistent without caching project configuration.
- **Storage Overview** performs an explicit, on-demand inventory across every installed plugin, measuring installed runtime directories and showing total disk usage, per-version paths and managed-project references.
- The “No managed references” filter is intentionally only a hint: Home configuration, unmanaged projects or other workflows may still depend on a version.
- Storage Overview results are transient and never scanned during normal startup.

### Projects

- Add/remove managed folders and search/sort by name, path, configured tool, or recent use.
- Favorite frequently used projects; favorites are pinned ahead of the normal sort and can be filtered independently.
- Recent-use timestamps are updated only by explicit project actions such as opening `.tool-versions`, revealing the folder, or running Install Missing.
- Card-based project status with Installed / Missing / System / Local path / Plugin missing / Unknown states.
- Reveal any managed project directly in Finder.
- Visual `.tool-versions` management without exposing a raw text editor.
- Add/edit/reorder fallback chains through `asdf set <tool> <version...>` in the project directory.
- Delete-one-tool is the only guarded `.tool-versions` direct-file exception because asdf 0.20 has no delete-entry command; it preserves unrelated lines/comments/permissions and rejects stale or duplicate target entries.
- Install Missing uses deterministic fallback planning, streaming logs, cancellation, and the application-wide write gate.

### Versions

- Installed versions are always shown before the full available catalog.
- Browse installed/latest/available versions with search and filtering.
- Install/uninstall exact runtime versions with live logs and cancellation.
- Uninstall shows managed-project usage impact before confirmation.
- **Runtime Storage** measures installed runtime directories on demand using paths reported by `asdf where <tool> <version>`, shows per-version disk usage and managed-project references, and can reveal an install path in Finder.
- Runtime Storage never deletes directories directly. Cleanup reuses the existing guarded `asdf uninstall <tool> <version>` workflow and global mutation gate.
- Runtime storage scanning runs off the main thread, does not follow nested symlinks, and is never performed during normal startup.
- **Runtime Update Center** compares every installed plugin with `asdf latest`; installing an update installs that exact latest version without removing older versions or rewriting `.tool-versions`.
- Health and other workflows can deep-link into Versions and preselect the relevant tool.
- Set exact versions at three scopes:
  - current Project: `asdf set <tool> <version>`;
  - closest existing parent configuration: `asdf set -p <tool> <version>`;
  - Home default: `asdf set -u <tool> <version>`.
  Parent mode previews the exact ancestor `.tool-versions` file before writing.

### Resolution and environment

- `asdf current [tool]` explains the effective version, source configuration and install state in Home or any managed project.
- `asdf which <command>` and `asdf shimversions <command>` explain the executable and shim providers for commands such as `node`, `npm`, `python` or `yarn`.
- **Environment Inspector** wraps `asdf env <command>` and compares Home vs selected-project `PATH`, `ASDF_*` and plugin-provided variables. It is deliberately limited to shimmed commands rather than exposing an arbitrary shell.

### Project Health

The Overview page links to a full **Project Health** report. It combines `.tool-versions` requirements with `asdf current` to surface missing plugins, missing runtimes when no fallback is usable, unknown lookup state, unreadable/empty configuration, effective runtimes reported as not installed, and the parent/Home `.tool-versions` files actually supplying inherited versions.

Health offers explicit, per-issue repair actions only when the remedy is deterministic:

- **Plugin missing** → on demand, query `asdf plugin list all`, require an exact plugin-name match when available, and prefer the catalog's explicit Git URL before confirmation; only fall back to short-name installation when no usable exact catalog URL is available.
- **Runtime missing** → confirm and install the first missing configured fallback with `asdf install <tool> <version>`.

There is intentionally no **Fix All**. Health repairs reuse the global mutation gate and live task logs, never silently rewrite `.tool-versions`, and leave uncertain states such as lookup failures as diagnostics instead of guessing.

Health cards can also navigate directly to the relevant managed Project, open Plugin Manager, or jump to Versions with the affected tool selected. The full resolution scan is on demand so normal startup stays lightweight.

### asdf machine configuration (`.asdfrc`)

**asdf Configuration…** provides a structured editor for the six standard asdf 0.20 machine settings:

- `legacy_version_file`;
- `use_release_candidates`;
- `always_keep_download`;
- `plugin_repository_last_check_duration` (`0`, a minute interval, or `never`);
- `disable_plugin_short_name_repository`;
- `concurrency` (`auto` or a positive core count).

The editor uses `$HOME/.asdfrc` unless `ASDF_CONFIG_FILE` points to an absolute custom path, and warns when `ASDF_CONCURRENCY` overrides the saved concurrency value. It never exposes a raw text editor. Saving updates only those six known keys, preserves unrelated comments/custom settings/plugin hooks and POSIX permissions, and aborts if the file changed after it was loaded.

asdf does not expose a CLI command for changing `.asdfrc`, so this is a documented, narrowly scoped direct-file configuration workflow rather than a shell-command wrapper.

### Plugins and diagnostics

- Plugin Manager: Add / Discover / Update / Update All / Remove.
- Search the official `asdf plugin list all` catalog and install entries without memorizing plugin names.
- Plugin Discovery opens with search focused, supports single-row selection and a Return/default action for the selected plugin.
- Plugin removal enumerates installed runtimes and managed-project impact first.
- Diagnostics: `asdf info`, `asdf where`, `asdf which`, `asdf reshim`, plus a copyable diagnostic report.

### Shell integration and completions

- **Shell Integration** manages only the app-owned PATH/shims marker block for Zsh (`~/.zshrc`) or Bash (`~/.bash_profile`).
- **Shell Completions…** (`⌘⇧C`) is a separate, explicit workflow; completions are never silently added as a side effect of PATH setup.
- Bash completion uses the current binary interface: `. <(asdf completion bash)`, pinned to the exact asdf executable selected by the GUI.
- Zsh completion runs `asdf completion zsh`, writes the generated script to `${ASDF_DATA_DIR:-$HOME/.asdf}/completions/_asdf` (using an inherited absolute `ASDF_DATA_DIR` when available), and manages only its own `fpath` / `compinit` marker block in `~/.zshrc`.
- Zsh completion content is compared with fresh `asdf completion zsh` output, so an asdf upgrade can surface **Update available**.
- Before applying, the GUI verifies that both the shell configuration and generated completion file have not changed since preview.
- Removing completions deletes only the GUI-owned shell block. The generated `_asdf` file is intentionally retained so the app never deletes a completion file another shell framework may also use.

### Navigation and accessibility

- The main sidebar uses shared navigation state so cross-feature actions can return to the correct management screen with context.
- `⌘1` Overview, `⌘2` Projects, `⌘3` Versions, `⌘4` Resolution, `⌘5` Plugins.
- `⌘⇧C` opens Shell Completions; existing feature-window shortcuts remain available from the app menu.
- Project and version status rows expose explicit textual state in addition to color/icon styling.
- Favorites, recent-use state, runtime disk usage and project-reference counts are exposed as text/VoiceOver semantics rather than color-only state.
- Core project/version controls include VoiceOver labels or hints, Health severity is displayed as text rather than color alone, and the completion workflow exposes explicit status/file descriptions.
- English / Simplified Chinese switching continues to apply to navigation, cross-feature actions, completion management, project activity, runtime storage, and accessibility copy.

### Onboarding and localization

- Dedicated missing-asdf setup screen.
- Verified in-app installation from official asdf GitHub release assets to `~/.local/bin/asdf`, including SHA-256 verification and no `sudo`/Homebrew requirement.
- Explicit Zsh/Bash Shell Integration with preview, managed markers, race protection and removal support.
- One-time Getting Started guide.
- English / Simplified Chinese in-app language switching without restart.
- About window with app/asdf information and GitHub Release update checking, including the current prerelease channel.

## Safety model

- SwiftUI views do not construct shell command strings.
- Normal asdf commands are typed behind `AsdfService`; process execution is behind `AsdfCommandRunner`.
- Commands use `Process.executableURL` + argument arrays, not `/bin/zsh -c` interpolation.
- Only one mutation/bootstrap/configuration operation runs application-wide at a time.
- Potentially destructive runtime/plugin removal shows known impact first.
- Runtime Storage and Storage Overview are read-only except when the user explicitly chooses cleanup, which routes through the existing typed `asdf uninstall` operation; the app never recursively deletes an asdf runtime directory.
- “No managed project references” is never treated as proof that a runtime is unused outside the GUI's managed project set.
- `.tool-versions` remains deterministic: Update Center never writes `latest` into project files.
- Structured `.asdfrc` writes are race-checked and limited to the six documented standard keys; unknown lines and plugin hooks are preserved.
- Shell completion writes are previewed, marker-scoped, race-checked, and participate in the same global mutation gate.

## Run from source

```bash
swift test
swift run asdf-gui
```

You can also open `Package.swift` directly in Xcode.

## Download / distribution

The release pipeline supports two modes:

- **Ad-hoc prerelease** — no paid Apple Developer account required. The app is ad-hoc signed for bundle integrity but is not Apple-notarized. On first launch use **Control-click / right-click the app → Open → Open**.
- **Developer ID release** — automatically enabled later when all documented Apple signing/notarization secrets are configured.

Both modes build separate Apple Silicon (`arm64`) and Intel (`x86_64`) DMGs plus `SHA256SUMS.txt`. See [`docs/RELEASING.md`](docs/RELEASING.md).

## Local package build

```bash
rm -rf dist
VERSION=0.0.0-dev BUILD_NUMBER=1 OUTPUT_DIR="$PWD/dist" SIGN_IDENTITY=- \
  bash scripts/build-app.sh
SIGN_IDENTITY=- \
  bash scripts/create-dmg.sh \
    "dist/asdf GUI.app" \
    "dist/asdf-gui-0.0.0-dev-macos-$(uname -m)-adhoc.dmg"
```

## Development

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before architectural changes or Codex follow-up work. It defines typed command boundaries, `.tool-versions` and `.asdfrc` mutation rules, shell integration/completion ownership, project activity persistence, runtime-storage safety, the global write gate, localization, navigation/deep-link behavior, accessibility expectations, Resolution/Environment/Health behavior, repair-action guarantees, update-center behavior and distribution contracts.
