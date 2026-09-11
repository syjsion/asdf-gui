import SwiftUI

private enum VersionListScope: String, CaseIterable, Identifiable {
    case all
    case installed

    var id: String { rawValue }
}

private struct PendingRuntimeUninstall {
    let tool: String
    let version: String
}

@MainActor
struct VersionsPolishedView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationModel.self) private var appNavigation
    @State private var selectedTool: String?
    @State private var searchText = ""
    @State private var scope: VersionListScope = .all
    @State private var isShowingUpdateCenter = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Versions")
                        .font(.largeTitle.bold())
                    Text("Browse, install, and uninstall versions for each installed plugin.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoadingVersionBrowser {
                    ProgressView().controlSize(.small)
                }
                Button(language.localized("Update Center"), systemImage: "arrow.up.circle") {
                    isShowingUpdateCenter = true
                }
                .disabled(model.plugins.isEmpty || model.hasActiveOperation)
                .accessibilityHint(Text(language.localized("Compare installed runtimes with the latest stable versions.")))

                Button("Refresh", systemImage: "arrow.clockwise") {
                    guard let selectedTool else { return }
                    Task { await model.loadVersionBrowser(tool: selectedTool) }
                }
                .disabled(selectedTool == nil || model.isLoadingVersionBrowser || model.hasActiveOperation)
                .accessibilityHint(Text(language.localized("Reload installed, latest, and available versions for the selected plugin.")))
            }

            if let task = model.activeVersionOperation {
                VersionOperationPanel(task: task)
            } else if model.activeInstallTask?.isRunning == true {
                Label(
                    "A project install task is running. Version actions are temporarily disabled.",
                    systemImage: "hourglass"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if model.plugins.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    "No plugins",
                    systemImage: "shippingbox",
                    description: Text("Install an asdf plugin before browsing runtime versions.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(model.plugins, selection: $selectedTool) { plugin in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plugin.name)
                                .fontWeight(.medium)
                            let count = model.installedVersionsByTool[plugin.name]?.count ?? 0
                            if count > 0 {
                                Text(installedCountText(count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(plugin.name)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(pluginAccessibilityLabel(plugin.name)))
                    }
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 270)
                    .disabled(model.hasActiveOperation)

                    VersionDetailView(
                        searchText: searchText,
                        scope: scope,
                        language: language
                    )
                    .frame(minWidth: 460)
                }
            }
        }
        .padding(28)
        .searchable(text: $searchText, prompt: "Filter versions")
        .toolbar {
            ToolbarItem {
                Picker("Scope", selection: $scope) {
                    Text("All").tag(VersionListScope.all)
                    Text("Installed").tag(VersionListScope.installed)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityLabel(Text(language.localized("Version list scope")))
            }
        }
        .sheet(isPresented: $isShowingUpdateCenter) {
            RuntimeUpdateCenterView()
        }
        .onAppear {
            applyVersionToolRequestIfNeeded()
            if selectedTool == nil {
                selectedTool = model.plugins.first?.name
            }
        }
        .onChange(of: model.plugins) { _, plugins in
            applyVersionToolRequestIfNeeded()
            if let selectedTool, plugins.contains(where: { $0.name == selectedTool }) {
                return
            }
            selectedTool = plugins.first?.name
        }
        .onChange(of: appNavigation.versionToolRequest) { _, _ in
            applyVersionToolRequestIfNeeded()
        }
        .task(id: selectedTool) {
            guard let selectedTool else {
                model.resetVersionBrowser()
                return
            }
            await model.loadVersionBrowser(tool: selectedTool)
        }
    }

    private func applyVersionToolRequestIfNeeded() {
        guard let requested = appNavigation.consumeVersionToolRequest() else { return }
        if model.plugins.contains(where: { $0.name == requested }) {
            selectedTool = requested
        }
    }

    private func installedCountText(_ count: Int) -> String {
        language == .simplifiedChinese ? "已安装 \(count) 个" : "\(count) installed"
    }

    private func pluginAccessibilityLabel(_ name: String) -> String {
        let count = model.installedVersionsByTool[name]?.count ?? 0
        return "\(name), \(installedCountText(count))"
    }
}

@MainActor
private struct VersionDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingUninstall: PendingRuntimeUninstall?
    @State private var isShowingUninstallConfirmation = false

    let searchText: String
    let scope: VersionListScope
    let language: AppLanguage

    private var records: [ToolVersionRecord] {
        var result = VersionCatalog.records(
            available: model.versionBrowserAvailableVersions,
            installed: model.versionBrowserInstalledVersions,
            latest: model.versionBrowserLatestVersion
        )

        if scope == .installed {
            result = result.filter(\.isInstalled)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.version.localizedCaseInsensitiveContains(query) }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let tool = model.versionBrowserTool {
                HStack(alignment: .firstTextBaseline) {
                    Text(tool).font(.title2.bold())
                    Spacer()
                    Text(installedCountText(model.versionBrowserInstalledVersions.count))
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    LabeledContent("Installed", value: "\(model.versionBrowserInstalledVersions.count)")
                    Divider()
                    LabeledContent("Latest", value: model.versionBrowserLatestVersion ?? "—")
                    Divider()
                    LabeledContent("Available", value: "\(model.versionBrowserAvailableVersions.count)")
                }

                if !model.versionBrowserErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.versionBrowserErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }

                if records.isEmpty && !model.isLoadingVersionBrowser {
                    ContentUnavailableView(
                        scope == .installed ? "No installed versions" : "No matching versions",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text(searchText.isEmpty ? "No versions were returned for this plugin." : "Try a different search term.")
                    )
                } else {
                    Table(records) {
                        TableColumn("Version") { record in
                            Text(record.version)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        TableColumn("Status") { record in
                            HStack(spacing: 8) {
                                if record.isInstalled {
                                    Label("Installed", systemImage: "checkmark.circle.fill")
                                }
                                if record.isLatest {
                                    Label("Latest", systemImage: "star.fill")
                                }
                                if !record.isInstalled && !record.isLatest {
                                    Text("Available")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text(statusAccessibilityLabel(record)))
                        }
                        TableColumn("Action") { record in
                            if record.isInstalled {
                                Button(role: .destructive) {
                                    pendingUninstall = PendingRuntimeUninstall(tool: tool, version: record.version)
                                    isShowingUninstallConfirmation = true
                                } label: {
                                    Label("Uninstall", systemImage: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.hasActiveOperation)
                                .accessibilityLabel(Text(uninstallAccessibilityLabel(tool: tool, version: record.version)))
                            } else {
                                Button {
                                    model.installVersionFromBrowser(tool: tool, version: record.version)
                                } label: {
                                    Label("Install", systemImage: "arrow.down.circle")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.hasActiveOperation || model.executableURL == nil)
                                .accessibilityLabel(Text(installAccessibilityLabel(tool: tool, version: record.version)))
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a plugin",
                    systemImage: "shippingbox",
                    description: Text("Choose an installed asdf plugin to browse its versions.")
                )
            }
        }
        .padding(.leading, 12)
        .alert(
            "Uninstall version?",
            isPresented: $isShowingUninstallConfirmation,
            presenting: pendingUninstall
        ) { request in
            Button("Uninstall", role: .destructive) {
                model.uninstallVersionFromBrowser(tool: request.tool, version: request.version)
                pendingUninstall = nil
            }
            Button("Cancel", role: .cancel) {
                pendingUninstall = nil
            }
        } message: { request in
            Text(uninstallMessage(for: request))
        }
    }

    private func installedCountText(_ count: Int) -> String {
        language == .simplifiedChinese ? "已安装 \(count) 个" : "\(count) installed"
    }

    private func statusAccessibilityLabel(_ record: ToolVersionRecord) -> String {
        var parts: [String] = [record.version]
        if record.isInstalled { parts.append(language.localized("Installed")) }
        if record.isLatest { parts.append(language.localized("Latest")) }
        if !record.isInstalled && !record.isLatest { parts.append(language.localized("Available")) }
        return parts.joined(separator: ", ")
    }

    private func installAccessibilityLabel(tool: String, version: String) -> String {
        if language == .simplifiedChinese { return "安装 \(tool) \(version)" }
        return "Install \(tool) \(version)"
    }

    private func uninstallAccessibilityLabel(tool: String, version: String) -> String {
        if language == .simplifiedChinese { return "卸载 \(tool) \(version)" }
        return "Uninstall \(tool) \(version)"
    }

    private func uninstallMessage(for request: PendingRuntimeUninstall) -> String {
        let projects = model.projectsUsing(tool: request.tool, version: request.version)
        if language == .simplifiedChinese {
            guard !projects.isEmpty else {
                return "这会从 asdf 中移除 \(request.tool) \(request.version)。如需再次使用，必须重新安装。"
            }
            let projectList = projects.map { "• \($0.name) — \($0.path)" }.joined(separator: "\n")
            return "该版本被 \(projects.count) 个已管理项目引用：\n\n\(projectList)\n\n卸载后，如果没有其他可用 fallback，这些项目可能会缺少运行时。"
        }

        guard !projects.isEmpty else {
            return "This removes \(request.tool) \(request.version) from asdf. Reinstalling will be required to use it again."
        }
        let projectList = projects.map { "• \($0.name) — \($0.path)" }.joined(separator: "\n")
        return "This version is referenced by \(projects.count) managed project\(projects.count == 1 ? "" : "s"):\n\n\(projectList)\n\nUninstalling may leave those projects with a missing runtime unless another configured fallback remains usable."
    }
}
