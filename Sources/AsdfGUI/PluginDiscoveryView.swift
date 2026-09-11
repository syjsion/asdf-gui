import SwiftUI

@MainActor
struct PluginDiscoveryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var discovery = PluginDiscoveryModel()
    @State private var searchText = ""
    @State private var selectedPluginID: String?
    @FocusState private var isSearchFocused: Bool

    let operationModel: PluginManagementModel

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var filteredCatalog: [AsdfPluginCatalogEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return discovery.catalog }
        return discovery.catalog.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
                || (entry.url?.localizedCaseInsensitiveContains(query) == true)
        }
    }

    private var installedNames: Set<String> {
        Set(appModel.plugins.map(\.name))
    }

    private var selectedEntry: AsdfPluginCatalogEntry? {
        guard let selectedPluginID else { return nil }
        return filteredCatalog.first(where: { $0.id == selectedPluginID })
    }

    private var canInstallSelected: Bool {
        guard let selectedEntry else { return false }
        return !installedNames.contains(selectedEntry.name)
            && !operationModel.isBusy
            && !appModel.hasActiveOperation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.localized("Discover Plugins"))
                        .font(.largeTitle.bold())
                    Text(language.localized("Search the official asdf short-name plugin catalog and install without memorizing plugin names."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if discovery.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button(language.localized("Refresh"), systemImage: "arrow.clockwise") {
                    Task { await reloadCatalog() }
                }
                .disabled(discovery.isLoading)
                .accessibilityHint(Text(language == .simplifiedChinese ? "重新加载 asdf 官方插件目录。" : "Reload the official asdf plugin catalog."))

                Button(language.localized("Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            TextField(language.localized("Search plugins"), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .accessibilityHint(Text(language == .simplifiedChinese ? "按插件名或仓库 URL 筛选；Tab 可移动到结果表格。" : "Filter by plugin name or repository URL; press Tab to move to the results table."))

            if let error = discovery.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text(language == .simplifiedChinese ? "插件目录错误：\(error)" : "Plugin catalog error: \(error)"))
            }

            if filteredCatalog.isEmpty && !discovery.isLoading {
                ContentUnavailableView(
                    language.localized(discovery.catalog.isEmpty ? "No plugin catalog" : "No matching plugins"),
                    systemImage: "shippingbox.and.arrow.backward",
                    description: Text(language.localized(discovery.catalog.isEmpty
                        ? "Refresh to load asdf plugin list all."
                        : "Try another plugin name or repository URL."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredCatalog, selection: $selectedPluginID) {
                    TableColumn(language.localized("Plugin")) { entry in
                        HStack(spacing: 8) {
                            Text(entry.name).fontWeight(.medium)
                            if installedNames.contains(entry.name) {
                                Label(language.localized("Installed"), systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(Text(pluginAccessibilityLabel(entry)))
                    }
                    TableColumn(language.localized("Repository")) { entry in
                        Text(entry.url ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    TableColumn(language.localized("Action")) { entry in
                        if installedNames.contains(entry.name) {
                            Text(language.localized("Installed")).foregroundStyle(.secondary)
                        } else {
                            Button(language.localized("Install")) {
                                install(entry)
                            }
                            .buttonStyle(.borderless)
                            .disabled(operationModel.isBusy || appModel.hasActiveOperation)
                            .accessibilityLabel(Text(installAccessibilityLabel(entry.name)))
                        }
                    }
                }

                HStack {
                    if let selectedEntry {
                        Text(selectedSummary(selectedEntry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(language == .simplifiedChinese ? "选择一个插件后可使用 Return 安装。" : "Select a plugin, then press Return to install it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(language == .simplifiedChinese ? "安装选中插件" : "Install Selected", systemImage: "plus.circle") {
                        guard let selectedEntry else { return }
                        install(selectedEntry)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canInstallSelected)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 560)
        .task {
            if discovery.catalog.isEmpty {
                await reloadCatalog()
            } else {
                selectFirstVisibleIfNeeded()
            }
            isSearchFocused = true
        }
        .onChange(of: searchText) { _, _ in
            selectFirstVisibleIfNeeded()
        }
        .onChange(of: discovery.catalog) { _, _ in
            selectFirstVisibleIfNeeded()
        }
    }

    private func reloadCatalog() async {
        await discovery.load(appModel: appModel)
        selectFirstVisibleIfNeeded()
    }

    private func selectFirstVisibleIfNeeded() {
        if let selectedPluginID, filteredCatalog.contains(where: { $0.id == selectedPluginID }) {
            return
        }
        selectedPluginID = filteredCatalog.first?.id
    }

    private func install(_ entry: AsdfPluginCatalogEntry) {
        guard !installedNames.contains(entry.name) else { return }
        operationModel.addPlugin(
            name: entry.name,
            gitURL: entry.url,
            appModel: appModel
        )
        dismiss()
    }

    private func pluginAccessibilityLabel(_ entry: AsdfPluginCatalogEntry) -> String {
        let state = installedNames.contains(entry.name)
            ? language.localized("Installed")
            : language.localized("Available")
        let repository = entry.url ?? (language == .simplifiedChinese ? "无仓库 URL" : "no repository URL")
        return "\(entry.name), \(state), \(repository)"
    }

    private func installAccessibilityLabel(_ name: String) -> String {
        language == .simplifiedChinese ? "安装插件 \(name)" : "Install plugin \(name)"
    }

    private func selectedSummary(_ entry: AsdfPluginCatalogEntry) -> String {
        if language == .simplifiedChinese {
            return installedNames.contains(entry.name)
                ? "已选择 \(entry.name)（已安装）"
                : "已选择 \(entry.name)"
        }
        return installedNames.contains(entry.name)
            ? "Selected \(entry.name) (installed)"
            : "Selected \(entry.name)"
    }
}
