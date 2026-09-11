import SwiftUI

@MainActor
struct PluginsHubView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Plugins", "插件"))
                        .font(.largeTitle.bold())
                    Text(t(
                        "Install, discover, update, and remove asdf plugins from the visible GUI.",
                        "直接在 GUI 中安装、发现、更新和移除 asdf 插件。"
                    ))
                    .foregroundStyle(.secondary)
                }
                Spacer()

                Button(t("Add / Manage Plugins", "添加 / 管理插件"), systemImage: "plus.circle") {
                    openWindow(id: "plugin-manager")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.hasActiveOperation)

                Button(t("Refresh", "刷新"), systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .disabled(model.hasActiveOperation)
            }

            GroupBox {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(t("Install a new runtime", "安装新的运行时"))
                            .font(.headline)
                        Text(t(
                            "First add the runtime's plugin, then choose its exact version in Versions. For Node.js, install the nodejs plugin first.",
                            "先添加运行时对应的插件，再到“版本”中选择并安装具体版本。例如安装 Node.js 时，先安装 nodejs 插件。"
                        ))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t("1. Add Plugin", "1. 添加插件"), systemImage: "shippingbox.and.arrow.down") {
                        openWindow(id: "plugin-manager")
                    }
                    .disabled(model.hasActiveOperation)
                    Button(t("2. Browse Versions", "2. 浏览版本"), systemImage: "square.stack.3d.up") {
                        navigation.show(.versions)
                    }
                    .disabled(model.plugins.isEmpty)
                }
            }

            if model.plugins.isEmpty && !model.isLoading {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        t("No plugins installed", "尚未安装插件"),
                        systemImage: "shippingbox",
                        description: Text(t(
                            "Add a plugin such as nodejs, python, ruby, or golang to start installing runtime versions.",
                            "先添加 nodejs、python、ruby、golang 等插件，然后即可安装对应运行时版本。"
                        ))
                    )
                    Button(t("Add Your First Plugin", "添加第一个插件"), systemImage: "plus") {
                        openWindow(id: "plugin-manager")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GroupBox(t("Installed Plugins", "已安装插件")) {
                    Table(model.plugins) {
                        TableColumn(t("Plugin", "插件")) { plugin in
                            Text(plugin.name)
                                .fontWeight(.medium)
                                .textSelection(.enabled)
                        }
                        TableColumn(t("Repository", "仓库")) { plugin in
                            Text(plugin.url ?? "—")
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        TableColumn(t("Versions", "版本")) { plugin in
                            Button(t("Open Versions", "打开版本")) {
                                navigation.showVersions(tool: plugin.name)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .frame(minHeight: 280)
                }
            }
        }
        .padding(28)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
