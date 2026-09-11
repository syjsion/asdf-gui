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
    @Environment(\.openWindow) private var openWindow
    @State private var selectedTool: String?
    @State private var searchText = ""
    @State private var scope: VersionListScope = .all
    @State private var isShowingUpdateCenter = false
    @State private var isShowingStorage = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.localized("Versions"))
                        .font(.largeTitle.bold())
                    Text(t(
                        "Browse installed plugins and manage exact runtime versions. Use Add Runtime for the simplest end-to-end installation flow.",
                        "浏览已安装插件并管理精确运行时版本。需要从零安装时，推荐使用“添加运行时”完成完整流程。"
                    ))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoadingVersionBrowser {
                    ProgressView().controlSize(.small)
                }

                Button(t("Add Runtime", "添加运行时"), systemImage: "plus.circle.fill") {
                    openWindow(id: "runtime-setup")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.hasActiveOperation)

                Button(language.localized("Runtime Storage"), systemImage: "internaldrive") {
                    isShowingStorage = true
                }
                .disabled(selectedTool == nil || model.versionBrowserInstalledVersions.isEmpty || model.hasActiveOperation)
                .accessibilityHint(Text(language.localized("Measure disk usage for installed versions of the selected plugin.")))

                Button(language.localized("Update Center"), systemImage: "arrow.up.circle") {
                    isShowingUpdateCenter = true
                }
                .disabled(model.plugins.isEmpty || model.hasActiveOperation)
                .accessibilityHint(Text(language.localized("Compare installed runtimes with the latest stable versions.")))

                Button(language.localized("Refresh"), systemImage: "arrow.clockwise") {
                    guard let selectedTool else { return }
                    Task {
                        await model.loadVersionBrowser(tool: selectedTool)
                        await model.refreshAllInstalledPluginVersions()
                    }
                }
                .disabled(selectedTool == nil || model.isLoadingVersionBrowser || model.hasActiveOperation)
                .accessibilityHint(Text(language.localized("Reload installed, latest, and available versions for the selected plugin.")))
            }

            if let task = model.activeVersionOperation {
                VersionOperationPanel(task: task)
            } else if model.activeInstallTask?.isRunning == true {
                Label(
                    t(
                        "A project install task is running. Version actions are temporarily disabled.",
                        "项目安装任务正在运行，版本操作暂时不可用。"
                    ),
                    systemImage: "hourglass"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if model.plugins.isEmpty && !model.isLoading {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        t("No runtimes yet", "还没有运行时"),
                        systemImage: "square.stack.3d.up.slash",
                        description: Text(t(
                            "Add Runtime will install the required plugin and let you choose an exact version in one flow.",
                            "使用“添加运行时”可以一次完成所需插件安装和精确版本选择。"
                        ))
                    )
                    Button(t("Add Runtime", "添加运行时"), systemImage: "plus") {
                        openWindow(id: "runtime-setup")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(model.plugins, selection: $selectedTool) { plugin in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plugin.name)
                                .fontWeight(.medium)
                            let count = model.installedVersionsByTool[plugin.name]?.count ?? 0
                            Text(installedCountText(count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
        .searchable(text: $searchText, prompt: language.localized("Filter versions"))
        .toolbar {
            ToolbarItem {
                Picker(language.localized("Scope"), selection: $scope) {
                    Text(language.localized("All")).tag(VersionListScope.all)
                    Text(language.localized("Installed")).tag(VersionListScope.installed)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityLabel(Text(language.localized("Version list scope")))
            }
        }
        .sheet(isPresented: $isShowingUpdateCenter) {
            RuntimeUpdateCenterView()
        }
        .sheet(isPresented: $isShowingStorage) {
            if let selectedTool {
                RuntimeStorageView(tool: selectedTool)
            }
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
                Task { await model.refreshAllInstalledPluginVersions() }
                return
            }
            selectedTool = plugins.first?.name
            Task { await model.refreshAllInstalledPluginVersions() }
        }
        .onChange(of: appNavigation.versionToolRequest) { _, _ in
            applyVersionToolRequestIfNeeded()
        }
        .task {
            await model.refreshAllInstalledPluginVersions()
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

    private func t(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
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
                    LabeledContent(language.localized("Installed"), value: "\(model.versionBrowserInstalledVersions.count)")
                    Divider()
                    LabeledContent(language.localized("Latest"), value: model.versionBrowserLatestVersion ?? "—")
                    Divider()
                    LabeledContent(language.localized("Available"), value: "\(model.versionBrowserAvailableVersions.count)")
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
                        scope == .installed ? language.localized("No installed versions") : language.localized("No matching versions"),
                        systemImage: "square.stack.3d.up.slash",
                        description: Text(searchText.isEmpty
                                          ? language.localized("No versions were returned for this plugin.")
                                          : language.localized("Try a different search term."))
                    )
                } else {
                    Table(records) {
                        TableColumn(language.localized("Version")) { record in
                            Text(record.version)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        TableColumn(language.localized("Status")) { record in
                            HStack(spacing: 8) {
                                if record.isInstalled {
                                    Label(language.localized("Installed"), systemImage: "checkmark.circle.fill")
                                }
                                if record.isLatest {
                                    Label(language.localized("Latest"), systemImage: "star.fill")
                                }
                                if !record.isInstalled && !record.isLatest {
                                    Text(language.localized("Available"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text(statusAccessibilityLabel(record)))
                        }
                        TableColumn(language.localized("Action")) { record in
                            if record.isInstalled {
                                Button(role: .destructive) {
                                    pendingUninstall = PendingRuntimeUninstall(tool: tool, version: record.version)
                                    isShowingUninstallConfirmation = true
                                } label: {
                                    Label(language.localized("Uninstall"), systemImage: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.hasActiveOperation)
                                .accessibilityLabel(Text(uninstallAccessibilityLabel(tool: tool, version: record.version)))
                            } else {
                                Button {
                                    model.installVersionFromBrowser(tool: tool, version: record.version)
                                } label: {
                                    Label(language.localized("Install"), systemImage: "arrow.down.circle")
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
                    language.localized("Select a plugin"),
                    systemImage: "shippingbox",
                    description: Text(language.localized("Choose an installed asdf plugin to browse its versions."))
                )
            }
        }
        .padding(.leading, 12)
        .alert(
            language.localized("Uninstall version?"),
            isPresented: $isShowingUninstallConfirmation,
            presenting: pendingUninstall
        ) { request in
            Button(language.localized("Uninstall"), role: .destructive) {
                model.uninstallVersionFromBrowser(tool: request.tool, version: request.version)
                pendingUninstall = nil
            }
            Button(language.localized("Cancel"), role: .cancel) {
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
