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
                        "Plugins are the adapters asdf uses for each runtime. Most users can install runtimes with Add Runtime and let the app handle plugin setup automatically.",
                        "插件是 asdf 管理各类运行时所需的适配器。多数情况下直接使用“添加运行时”即可，由应用自动处理插件安装。"
                    ))
                    .foregroundStyle(.secondary)
                }
                Spacer()

                Button(t("Add Runtime", "添加运行时"), systemImage: "plus.circle.fill") {
                    openWindow(id: "runtime-setup")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.hasActiveOperation)

                Button(t("Manage Plugins", "管理插件"), systemImage: "shippingbox") {
                    openWindow(id: "plugin-manager")
                }
                .disabled(model.hasActiveOperation)

                Button(t("Refresh", "刷新"), systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .disabled(model.hasActiveOperation)
            }

            GroupBox {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(t("New to asdf plugins?", "不熟悉 asdf 插件？"))
                            .font(.headline)
                        Text(t(
                            "You do not need to install a plugin manually just to get Node.js, Python, Ruby, Go, or Java. Add Runtime combines plugin setup, exact version installation, and optional project/Home configuration.",
                            "如果只是想安装 Node.js、Python、Ruby、Go 或 Java，不需要先手动理解插件。使用“添加运行时”即可完成插件、精确版本安装，以及可选的项目/Home 配置。"
                        ))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t("Add Runtime", "添加运行时"), systemImage: "arrow.right.circle") {
                        openWindow(id: "runtime-setup")
                    }
                    .disabled(model.hasActiveOperation)
                }
            }

            if model.plugins.isEmpty && !model.isLoading {
                VStack(spacing: 14) {
                    ContentUnavailableView(
                        t("No plugins installed", "尚未安装插件"),
                        systemImage: "shippingbox",
                        description: Text(t(
                            "Use Add Runtime for the guided path, or open Manage Plugins when you specifically want to work with plugin repositories.",
                            "推荐使用“添加运行时”向导；只有需要直接管理插件仓库时，再打开“管理插件”。"
                        ))
                    )
                    HStack(spacing: 10) {
                        Button(t("Add Runtime", "添加运行时"), systemImage: "plus") {
                            openWindow(id: "runtime-setup")
                        }
                        .buttonStyle(.borderedProminent)
                        Button(t("Manage Plugins", "管理插件"), systemImage: "shippingbox") {
                            openWindow(id: "plugin-manager")
                        }
                    }
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
                        TableColumn(t("Runtime Versions", "运行时版本")) { plugin in
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
