import SwiftUI

@MainActor
struct RuntimeSetupView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var setup = RuntimeSetupModel()
    @State private var pluginSearch = ""
    @State private var versionSearch = ""
    @FocusState private var pluginSearchFocused: Bool
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var filteredCatalog: [AsdfPluginCatalogEntry] {
        let query = pluginSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(setup.catalog.prefix(120)) }
        return Array(setup.catalog.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
                || (entry.url?.localizedCaseInsensitiveContains(query) ?? false)
        }.prefix(200))
    }

    private var selectedPluginInstalled: Bool {
        guard let tool = setup.selectedTool else { return false }
        return !RuntimeSetupPlanner.needsPluginInstall(tool: tool, plugins: appModel.plugins)
    }

    private var displayedVersions: [ToolVersionRecord] {
        guard let tool = setup.selectedTool else { return [] }
        let installed = appModel.installedVersionsByTool[tool] ?? []
        var records = VersionCatalog.records(
            available: setup.availableVersions,
            installed: installed,
            latest: setup.latestVersion
        )
        let query = versionSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            records = records.filter { $0.version.localizedCaseInsensitiveContains(query) }
            return Array(records.prefix(300))
        }

        var prioritized: [ToolVersionRecord] = []
        var seen = Set<String>()
        for record in records where record.isLatest || record.isInstalled {
            if seen.insert(record.version).inserted { prioritized.append(record) }
        }
        for record in records.reversed() where seen.insert(record.version).inserted {
            prioritized.append(record)
            if prioritized.count >= 160 { break }
        }
        return prioritized
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if setup.phase == .completed {
                completionView
            } else {
                HSplitView {
                    runtimeChooser
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 390)
                    setupDetail
                        .frame(minWidth: 520)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 650)
        .task {
            if setup.selectedProjectPath == nil {
                setup.selectedProjectPath = appModel.projects.first?.path
            }
            await setup.loadCatalog(appModel: appModel)
            pluginSearchFocused = true
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "plus.app.fill")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(t("Add Runtime", "添加运行时"))
                    .font(.title.bold())
                Text(t(
                    "Choose a runtime once; asdf GUI handles plugin setup, exact version installation, and optional project/Home configuration.",
                    "只需选择运行时；asdf GUI 会处理插件安装、精确版本安装，以及可选的项目/Home 配置。"
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if setup.isBusy {
                Button(t("Cancel Operation", "取消操作"), role: .cancel) {
                    setup.cancel()
                }
            }
            Button(t("Close", "关闭")) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(setup.isBusy)
        }
        .padding(22)
    }

    private var runtimeChooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("Choose a runtime", "选择运行时"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                ForEach(RuntimePreset.popular) { preset in
                    Button {
                        setup.select(tool: preset.tool, appModel: appModel)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: preset.symbol)
                                .font(.title2)
                            Text(preset.displayName)
                                .fontWeight(.medium)
                            Text(preset.tool)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 78)
                    }
                    .buttonStyle(.plain)
                    .background(
                        setup.selectedTool == preset.tool ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(setup.selectedTool == preset.tool ? Color.accentColor : Color.clear, lineWidth: 1)
                    }
                }
            }

            Divider()

            TextField(t("Search all plugins", "搜索所有插件"), text: $pluginSearch)
                .textFieldStyle(.roundedBorder)
                .focused($pluginSearchFocused)

            if setup.phase == .loadingCatalog {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(t("Loading plugin catalog…", "正在加载插件目录…"))
                        .foregroundStyle(.secondary)
                }
            } else if let catalogError = setup.catalogError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(catalogError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(t("Retry Catalog", "重试插件目录")) {
                        Task { await setup.loadCatalog(appModel: appModel, force: true) }
                    }
                }
            }

            List(filteredCatalog) { entry in
                Button {
                    setup.select(tool: entry.name, appModel: appModel)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: setup.selectedTool == entry.name ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(setup.selectedTool == entry.name ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.name)
                                    .fontWeight(.medium)
                                if appModel.plugins.contains(where: { $0.name == entry.name }) {
                                    Text(t("Installed", "已安装"))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                            if let url = entry.url {
                                Text(url)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(entry.name), \(appModel.plugins.contains(where: { $0.name == entry.name }) ? t("installed", "已安装") : t("available", "可用"))"))
            }
            .listStyle(.inset)

            if pluginSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && setup.catalog.count > 120 {
                Text(t("Showing popular catalog entries. Search to find any plugin.", "当前显示部分插件；使用搜索可查找完整目录。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var setupDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let tool = setup.selectedTool {
                    selectedRuntimeHeader(tool: tool)
                    pluginReadiness(tool: tool)

                    if selectedPluginInstalled {
                        versionSection(tool: tool)
                    }

                    if let selectedVersion = setup.selectedVersion, selectedPluginInstalled {
                        destinationSection(tool: tool, version: selectedVersion)
                    }

                    if let error = setup.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .textSelection(.enabled)
                    }

                    if !setup.log.isEmpty {
                        DisclosureGroup(t("Operation Details", "操作详情")) {
                            ScrollView {
                                Text(setup.log)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(minHeight: 90, maxHeight: 180)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    ContentUnavailableView(
                        t("Choose a runtime", "选择一个运行时"),
                        systemImage: "plus.app",
                        description: Text(t(
                            "Start with Node.js, Python, Ruby, Go, Java, or search the complete asdf plugin catalog.",
                            "可以从 Node.js、Python、Ruby、Go、Java 开始，也可以搜索完整的 asdf 插件目录。"
                        ))
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                }
            }
            .padding(22)
        }
    }

    private func selectedRuntimeHeader(tool: String) -> some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(for: tool))
                        .font(.title2.bold())
                    Text(tool)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    if let url = setup.selectedGitURL {
                        Text(url)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                Label(
                    selectedPluginInstalled ? t("Plugin installed", "插件已安装") : t("Plugin required", "需要安装插件"),
                    systemImage: selectedPluginInstalled ? "checkmark.circle.fill" : "shippingbox.and.arrow.down"
                )
                .foregroundStyle(selectedPluginInstalled ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
            }
            .padding(.vertical, 3)
        }
    }

    @ViewBuilder
    private func pluginReadiness(tool: String) -> some View {
        if !selectedPluginInstalled {
            GroupBox(t("Step 1 · Plugin", "第 1 步 · 插件")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t(
                        "asdf needs the \(tool) plugin before it can list or install runtime versions.",
                        "asdf 需要先安装 \(tool) 插件，才能列出和安装对应的运行时版本。"
                    ))
                    .foregroundStyle(.secondary)
                    Button(t("Install Plugin & Continue", "安装插件并继续"), systemImage: "shippingbox.and.arrow.down") {
                        setup.installPluginAndContinue(appModel: appModel)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(setup.isBusy || appModel.hasActiveOperation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
            }
        }
    }

    @ViewBuilder
    private func versionSection(tool: String) -> some View {
        GroupBox(t("Step 2 · Version", "第 2 步 · 版本")) {
            VStack(alignment: .leading, spacing: 12) {
                if setup.phase == .loadingVersions {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(t("Loading available versions…", "正在加载可用版本…"))
                            .foregroundStyle(.secondary)
                    }
                } else if setup.availableVersions.isEmpty && setup.latestVersion == nil {
                    Button(t("Load Versions", "加载版本"), systemImage: "arrow.clockwise") {
                        Task { await setup.loadVersions(appModel: appModel) }
                    }
                    .disabled(setup.isBusy)
                } else {
                    if let latest = setup.latestVersion {
                        HStack {
                            Label(t("Latest stable", "最新稳定版"), systemImage: "star.fill")
                            Text(latest)
                                .font(.body.monospaced())
                            Spacer()
                            if setup.selectedVersion != latest {
                                Button(t("Use Latest", "使用最新版本")) {
                                    setup.selectedVersion = latest
                                }
                            }
                        }
                    }

                    TextField(t("Filter versions", "筛选版本"), text: $versionSearch)
                        .textFieldStyle(.roundedBorder)

                    List(displayedVersions) { record in
                        Button {
                            setup.selectedVersion = record.version
                        } label: {
                            HStack {
                                Image(systemName: setup.selectedVersion == record.version ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(setup.selectedVersion == record.version ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                                    .accessibilityHidden(true)
                                Text(record.version)
                                    .font(.body.monospaced())
                                Spacer()
                                if record.isInstalled {
                                    Text(t("Installed", "已安装"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if record.isLatest {
                                    Text(t("Latest", "最新"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: 190)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
        }
    }

    private func destinationSection(tool: String, version: String) -> some View {
        GroupBox(t("Step 3 · Install & use", "第 3 步 · 安装并使用")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(t("After installation", "安装后"), selection: $setup.destination) {
                    Text(t("Install only", "仅安装")).tag(RuntimeSetupDestination.installOnly)
                    Text(t("Use as Home default", "设为 Home 默认")).tag(RuntimeSetupDestination.home)
                    Text(t("Use in a project", "用于项目")).tag(RuntimeSetupDestination.project)
                }
                .pickerStyle(.segmented)

                if setup.destination == .project {
                    if appModel.projects.isEmpty {
                        Label(t(
                            "Add a managed project first, or choose Install only / Home default.",
                            "请先添加已管理项目，或选择“仅安装”/“Home 默认”。"
                        ), systemImage: "folder.badge.plus")
                        .foregroundStyle(.orange)
                    } else {
                        Picker(t("Project", "项目"), selection: $setup.selectedProjectPath) {
                            ForEach(appModel.projects) { project in
                                Text(project.name).tag(Optional(project.path))
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summaryTitle(tool: tool, version: version))
                            .font(.headline)
                        Text(summaryDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(primaryActionTitle, systemImage: "arrow.down.circle.fill") {
                        setup.installSelectedRuntime(appModel: appModel)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        setup.isBusy
                            || appModel.hasActiveOperation
                            || (setup.destination == .project && setup.selectedProjectPath == nil)
                    )
                }
            }
            .padding(.vertical, 3)
        }
    }

    private var completionView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 58))
                .foregroundStyle(.secondary)
            Text(t("Runtime ready", "运行时已就绪"))
                .font(.largeTitle.bold())
            if let tool = setup.selectedTool, let version = setup.selectedVersion {
                Text("\(displayName(for: tool)) · \(version)")
                    .font(.title3.monospaced())
                Text(completionDetail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
            }
            HStack(spacing: 12) {
                Button(t("Add Another Runtime", "继续添加运行时")) {
                    setup.startOver(appModel: appModel)
                    pluginSearch = ""
                    versionSearch = ""
                    pluginSearchFocused = true
                }
                Button(t("Open Versions", "打开版本页面"), systemImage: "square.stack.3d.up") {
                    if let tool = setup.selectedTool {
                        navigation.showVersions(tool: tool)
                    } else {
                        navigation.show(.versions)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var primaryActionTitle: String {
        guard let tool = setup.selectedTool, let version = setup.selectedVersion else {
            return t("Install Runtime", "安装运行时")
        }
        let installed = !RuntimeSetupPlanner.shouldInstallVersion(
            tool: tool,
            version: version,
            installedVersionsByTool: appModel.installedVersionsByTool
        )
        if installed && setup.destination != .installOnly {
            return t("Apply Version", "应用版本")
        }
        return t("Install Runtime", "安装运行时")
    }

    private var summaryDetail: String {
        switch setup.destination {
        case .installOnly:
            return t("Install the exact version without changing .tool-versions.", "安装精确版本，但不修改任何 .tool-versions。")
        case .home:
            return t("Install if needed, then write the exact version with asdf set -u.", "如有需要先安装，然后通过 asdf set -u 写入精确版本。")
        case .project:
            return t("Install if needed, then write the exact version in the selected project.", "如有需要先安装，然后把精确版本写入所选项目。")
        }
    }

    private var completionDetail: String {
        switch setup.destination {
        case .installOnly:
            return t("The runtime is installed. Project/Home configuration was left unchanged.", "运行时已经安装；项目和 Home 配置没有被修改。")
        case .home:
            return t("The runtime is installed and configured as the Home default.", "运行时已经安装，并设为 Home 默认版本。")
        case .project:
            return t("The runtime is installed and configured in the selected managed project.", "运行时已经安装，并写入所选已管理项目。")
        }
    }

    private func summaryTitle(tool: String, version: String) -> String {
        let name = displayName(for: tool)
        return t("Ready: \(name) \(version)", "准备安装：\(name) \(version)")
    }

    private func displayName(for tool: String) -> String {
        RuntimePreset.popular.first(where: { $0.tool == tool })?.displayName ?? tool
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
