import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ToolsHubView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationModel.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var isChoosingExecutable = false
    @State private var importerError: String?

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Settings & Tools", "设置与工具"))
                        .font(.largeTitle.bold())
                    Text(t(
                        "All setup, configuration, and troubleshooting features are available here without using the macOS menu bar.",
                        "所有安装、配置和诊断功能都可以直接从这里进入，不再需要先知道 macOS 菜单栏里还有隐藏入口。"
                    ))
                    .foregroundStyle(.secondary)
                }

                GroupBox(t("App & asdf", "应用与 asdf")) {
                    VStack(alignment: .leading, spacing: 14) {
                        LabeledContent(t("Interface language", "界面语言")) {
                            Picker("", selection: $languageRaw) {
                                ForEach(AppLanguage.allCases) { item in
                                    Text(item.displayName).tag(item.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }

                        Divider()

                        LabeledContent(t("Active asdf", "当前 asdf")) {
                            Text(model.executableURL?.path ?? t("Not detected", "未检测到"))
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        HStack {
                            Button(t("Choose asdf…", "选择 asdf…"), systemImage: "folder") {
                                isChoosingExecutable = true
                            }
                            Button(t("Use Automatic Detection", "使用自动检测"), systemImage: "scope") {
                                Task { await model.resetExecutablePreference() }
                            }
                            .disabled(model.configuredExecutableURL == nil)

                            Spacer()
                            Text(model.configuredExecutableURL == nil
                                 ? t("Automatic", "自动")
                                 : t("Custom executable", "自定义可执行文件"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let importerError {
                            Label(importerError, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox(t("Runtime management", "运行时管理")) {
                    toolGrid([
                        ToolAction(
                            title: t("Add Runtime", "添加运行时"),
                            description: t(
                                "Guided plugin + exact version installation for Node.js, Python, Ruby, Go, Java, and more.",
                                "通过向导安装 Node.js、Python、Ruby、Go、Java 等运行时，并自动处理插件与精确版本。"
                            ),
                            icon: "plus.circle.fill",
                            action: { openWindow(id: "runtime-setup") }
                        ),
                        ToolAction(
                            title: t("Manage Plugins", "管理插件"),
                            description: t("Discover, add, update, or remove asdf plugins.", "发现、添加、更新或移除 asdf 插件。"),
                            icon: "shippingbox",
                            action: { openWindow(id: "plugin-manager") }
                        ),
                        ToolAction(
                            title: t("Browse Versions", "浏览版本"),
                            description: t("Install or uninstall exact runtime versions.", "安装或卸载精确的运行时版本。"),
                            icon: "square.stack.3d.up",
                            action: { navigation.show(.versions) }
                        ),
                        ToolAction(
                            title: t("Set Runtime Version", "设置运行时版本"),
                            description: t("Choose Project, Parent, or Home version scope.", "选择 Project、Parent 或 Home 的版本作用域。"),
                            icon: "arrow.triangle.branch",
                            action: { openWindow(id: "version-selection") }
                        )
                    ])
                }

                GroupBox(t("Shell & asdf configuration", "Shell 与 asdf 配置")) {
                    toolGrid([
                        ToolAction(
                            title: t("Shell Integration", "Shell 集成"),
                            description: t("Manage the GUI-owned PATH and shims block.", "管理 GUI 自己维护的 PATH 与 shims 配置块。"),
                            icon: "terminal",
                            action: { openWindow(id: "shell-integration") }
                        ),
                        ToolAction(
                            title: t("Shell Completions", "Shell 自动补全"),
                            description: t("Configure Bash or Zsh completion explicitly.", "显式配置 Bash 或 Zsh 自动补全。"),
                            icon: "text.badge.checkmark",
                            action: { openWindow(id: "shell-completions") }
                        ),
                        ToolAction(
                            title: t("asdf Configuration", "asdf 配置"),
                            description: t("Edit supported .asdfrc settings structurally.", "以结构化方式编辑受支持的 .asdfrc 设置。"),
                            icon: "slider.horizontal.3",
                            action: { openWindow(id: "asdf-configuration") }
                        )
                    ])
                }

                GroupBox(t("Help & diagnostics", "帮助与诊断")) {
                    toolGrid([
                        ToolAction(
                            title: t("Diagnostics", "诊断"),
                            description: t("Inspect asdf info, where, which, and reshim workflows.", "检查 asdf info、where、which 和 reshim。"),
                            icon: "stethoscope",
                            action: { openWindow(id: "diagnostics") }
                        ),
                        ToolAction(
                            title: t("Getting Started", "开始使用"),
                            description: t("Reopen the first-run setup guide.", "重新打开首次使用指南。"),
                            icon: "sparkles",
                            action: { openWindow(id: "getting-started") }
                        ),
                        ToolAction(
                            title: t("About & Updates", "关于与更新"),
                            description: t("Check app version, asdf path, and available updates.", "查看应用版本、asdf 路径并检查更新。"),
                            icon: "info.circle",
                            action: { openWindow(id: "about") }
                        )
                    ])
                }
            }
            .padding(28)
        }
        .fileImporter(
            isPresented: $isChoosingExecutable,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importerError = nil
                Task { await model.setExecutable(url) }
            case .failure(let error):
                importerError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func toolGrid(_ actions: [ToolAction]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
            ForEach(actions) { item in
                Button(action: item.action) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.title3)
                            .frame(width: 26)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
                    .padding(12)
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(Text(item.title))
                .accessibilityHint(Text(item.description))
            }
        }
        .padding(.vertical, 4)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}

private struct ToolAction: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let action: () -> Void
}
