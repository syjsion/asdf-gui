# v1.0 Productization Contract

v1.0 treats asdf GUI as a product rather than a visual list of asdf commands. The CLI remains the source of truth, but common user goals should be discoverable without knowing asdf's plugin/runtime split in advance.

## Primary runtime workflow

The primary installation entry point is **Add Runtime** (`Command-N`). It is available from the main toolbar, Versions, Plugins, Settings & Tools, and Getting Started.

The guided flow is:

1. choose a popular runtime (Node.js, Python, Ruby, Go, Java) or search the full `asdf plugin list all` catalog;
2. if the plugin is missing, show that fact and explicitly install the exact-name catalog entry, preferring its Git URL;
3. load `asdf latest`, `asdf list all`, and current installed versions for the chosen plugin;
4. select an exact version; never persist `latest` as configuration;
5. immediately re-read `asdf list <tool>` before installation so stale UI state cannot cause an unnecessary duplicate install;
6. install with typed `asdf install <tool> <version>` only when the exact version is absent;
7. optionally leave configuration unchanged, write Home with `asdf set -u`, or write a selected managed project with `asdf set` in that project directory.

The wizard must participate in the same application-wide mutation gate as all other plugin/runtime writes. Plugin installation and runtime installation stream output and remain cancellable. It must not introduce shell-string command construction, `sudo`, direct asdf data-directory deletion, or implicit `.tool-versions` edits.

Advanced workflows remain available separately: Plugin Manager for repository-level plugin operations, Versions for detailed version browsing/storage/update work, and Set Runtime Version for Project/Parent/Home scope management.

## UI hierarchy

For normal users the product hierarchy is:

```text
Add Runtime
Projects
Versions
Resolution
Plugins (advanced adapter management)
Settings & Tools
```

Do not require users to discover macOS menu commands for core functionality. Menu commands and keyboard shortcuts are secondary accelerators, not the only entry points.

`Command-N` is reserved for Add Runtime. Main navigation remains `Command-1` through `Command-6`.

## Versions accuracy

Installed-version counts shown beside installed plugins are presentation state, but they must reflect all installed plugins rather than only tools referenced by managed projects. The Versions screen performs an on-demand all-plugin installed-version refresh. This should not be moved into normal application startup because it can make launch scale with plugin count.

The selected plugin still uses the detailed browser load for installed/latest/available versions and request isolation.

## Project activity consistency

Favorites and recent-use timestamps remain small UserDefaults-backed UI preferences. Multiple views that present this metadata must observe preference changes so toggling a favorite or marking recent use is reflected without requiring a view restart or manual refresh.

These preferences never change asdf state or project files.

## Runtime setup reliability

The wizard owns its transient selection/phase state. A running plugin/runtime mutation must not be redirected to a different tool/version by later UI selection. Write operations capture the intended tool, version, destination, and project before starting.

A project destination is valid only if the path is still in the managed-project list at write time. If it disappeared, fail instead of writing an arbitrary directory.

After successful plugin/runtime changes, refresh shared AppModel state from asdf rather than assuming the operation result is the complete current state.

## v1 release bar

Before merging a v1 productization PR:

- `swift test` must pass on the CI macOS runner;
- the release app bundle must compile successfully;
- ad-hoc code-sign verification must pass;
- the DMG must be created and `hdiutil verify` must pass;
- the PR head SHA used for merge must be the exact SHA that passed those jobs.

Before publishing `v1.0.0`, both arm64 and x86_64 release jobs and the final publish job must succeed. With no Apple Developer Program credentials, the release remains an ad-hoc prerelease and must not be described as notarized or Gatekeeper-trusted.
