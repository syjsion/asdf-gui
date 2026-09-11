import SwiftUI

@MainActor
struct OnboardingRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("asdfGUI.hasPresentedGettingStarted") private var hasPresentedGettingStarted = false

    var body: some View {
        RootContentView()
            .task { presentIfNeeded() }
            .onChange(of: model.executableURL?.path) { _, _ in presentIfNeeded() }
            .onChange(of: model.plugins) { _, _ in presentIfNeeded() }
    }

    private func presentIfNeeded() {
        guard !hasPresentedGettingStarted,
              !model.isLoading,
              model.executableURL != nil,
              model.plugins.isEmpty,
              model.projects.isEmpty else { return }
        hasPresentedGettingStarted = true
        openWindow(id: "getting-started")
    }
}

@MainActor
struct GettingStartedView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(language.localized("Getting Started"))
                        .font(.largeTitle.bold())
                    Text(t(
                        "Four steps from a working asdf installation to a runtime and your first managed project.",
                        "四步完成 asdf 环境、运行时安装以及第一个项目的管理。"
                    ))
                    .foregroundStyle(.secondary)
                }

                onboardingStep(
                    number: 1,
                    title: language.localized("asdf is ready"),
                    detail: asdfReadyDetail,
                    complete: model.executableURL != nil
                )

                onboardingStep(
                    number: 2,
                    title: language.localized("Connect your shell"),
                    detail: shellDetail,
                    complete: false,
                    actionTitle: language.localized("Shell Integration…")
                ) {
                    openWindow(id: "shell-integration")
                }

                onboardingStep(
                    number: 3,
                    title: t("Add a runtime", "添加运行时"),
                    detail: runtimeDetail,
                    complete: !model.plugins.isEmpty,
                    actionTitle: t("Add Runtime…", "添加运行时…")
                ) {
                    openWindow(id: "runtime-setup")
                }

                onboardingStep(
                    number: 4,
                    title: language.localized("Add your first project"),
                    detail: projectDetail,
                    complete: !model.projects.isEmpty
                )

                GroupBox(t("Safety by default", "默认安全原则")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            t(
                                "Shell files are never edited silently; Shell Integration always requires an explicit confirmation.",
                                "不会静默修改 Shell 文件；Shell Integration 始终需要明确确认。"
                            ),
                            systemImage: "doc.badge.gearshape"
                        )
                        Label(
                            t(
                                "Add Runtime shows which plugin, exact version, and scope will be used before configuration is changed.",
                                "“添加运行时”会在修改配置前明确展示插件、精确版本和作用域。"
                            ),
                            systemImage: "checkmark.shield"
                        )
                        Label(
                            t(
                                "Project/Home .tool-versions state is changed only by explicit version actions.",
                                "只有明确执行版本操作时，才会修改项目/Home 的版本配置。"
                            ),
                            systemImage: "slider.horizontal.3"
                        )
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 660, alignment: .leading)
            .padding(30)
            .frame(maxWidth: .infinity)
        }
    }

    private var asdfReadyDetail: String {
        if let executable = model.executableURL {
            return "\(model.asdfVersion) · \(executable.path)"
        }
        return t("Install or select asdf first.", "请先安装或选择 asdf。")
    }

    private var shellDetail: String {
        t(
            "Add the active asdf executable directory and asdf shims to Zsh or Bash PATH. The exact managed block is previewed before any file is changed.",
            "将当前 asdf 可执行文件目录和 asdf shims 加入 Zsh 或 Bash 的 PATH。修改任何文件前都会先预览完整托管配置块。"
        )
    }

    private var runtimeDetail: String {
        if model.plugins.isEmpty {
            return t(
                "Choose Node.js, Python, Ruby, Go, Java, or another runtime. The guided flow installs the plugin when needed, then installs an exact version and can optionally configure Home or a managed project.",
                "选择 Node.js、Python、Ruby、Go、Java 或其他运行时。向导会按需安装插件，再安装精确版本，并可选择配置 Home 或已管理项目。"
            )
        }
        return t(
            "You already have \(model.plugins.count) plugin\(model.plugins.count == 1 ? "" : "s"). Add Runtime can install another runtime or version without making you switch between Plugins and Versions manually.",
            "当前已安装 \(model.plugins.count) 个插件。“添加运行时”可以继续安装新的运行时或版本，无需手动在“插件”和“版本”之间切换。"
        )
    }

    private var projectDetail: String {
        if model.projects.isEmpty {
            return t(
                "Open Projects in the main sidebar and add a folder containing .tool-versions, or add an empty project and configure it visually.",
                "在主侧边栏打开“项目”，添加包含 .tool-versions 的文件夹；也可以添加空项目后再通过 GUI 配置。"
            )
        }
        return t(
            "\(model.projects.count) project\(model.projects.count == 1 ? "" : "s") managed.",
            "已管理 \(model.projects.count) 个项目。"
        )
    }

    @ViewBuilder
    private func onboardingStep(
        number: Int,
        title: String,
        detail: String,
        complete: Bool,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(complete ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tertiary.opacity(0.5)))
                    .frame(width: 30, height: 30)
                if complete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .disabled(model.hasActiveOperation)
                }
            }
            Spacer()
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
