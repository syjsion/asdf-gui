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
                    Text("Getting Started")
                        .font(.largeTitle.bold())
                    Text("A short path from a working asdf installation to your first managed project.")
                        .foregroundStyle(.secondary)
                }

                onboardingStep(
                    number: 1,
                    title: "asdf is ready",
                    detail: asdfReadyDetail,
                    complete: model.executableURL != nil
                )

                onboardingStep(
                    number: 2,
                    title: "Connect your shell",
                    detail: shellDetail,
                    complete: false,
                    actionTitle: "Shell Integration…"
                ) {
                    openWindow(id: "shell-integration")
                }

                onboardingStep(
                    number: 3,
                    title: "Add a plugin",
                    detail: pluginDetail,
                    complete: !model.plugins.isEmpty,
                    actionTitle: model.plugins.isEmpty ? "Open Plugin Manager…" : "Manage Plugins…"
                ) {
                    openWindow(id: "plugin-manager")
                }

                onboardingStep(
                    number: 4,
                    title: "Install a runtime",
                    detail: runtimeDetail,
                    complete: false
                )

                onboardingStep(
                    number: 5,
                    title: "Add your first project",
                    detail: projectDetail,
                    complete: !model.projects.isEmpty
                )

                GroupBox("What asdf GUI will not do automatically") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("It will not silently edit shell files; Shell Integration requires an explicit confirmation.", systemImage: "doc.badge.gearshape")
                        Label("It will not auto-install plugins when a project references a missing plugin.", systemImage: "shippingbox")
                        Label("It will not rewrite .tool-versions unless you explicitly use a version-selection action.", systemImage: "checkmark.shield")
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
        return language == .simplifiedChinese ? "请先安装或选择 asdf。" : "Install or select asdf first."
    }

    private var shellDetail: String {
        language == .simplifiedChinese
            ? "将当前 asdf 可执行文件目录和 asdf shims 加入 Zsh 或 Bash 的 PATH。修改任何文件前都会先预览完整托管配置块。"
            : "Add the active asdf executable directory and asdf shims to Zsh or Bash PATH. The exact managed block is previewed before any file is changed."
    }

    private var pluginDetail: String {
        if model.plugins.isEmpty {
            return language == .simplifiedChinese
                ? "插件告诉 asdf 如何安装 Node.js、Python 或 Ruby 等工具。"
                : "Plugins teach asdf how to install tools such as Node.js, Python, or Ruby."
        }
        return language == .simplifiedChinese
            ? "已安装 \(model.plugins.count) 个插件。"
            : "\(model.plugins.count) plugin\(model.plugins.count == 1 ? "" : "s") installed."
    }

    private var runtimeDetail: String {
        if language == .simplifiedChinese {
            return model.plugins.isEmpty
                ? "添加插件后，在主侧边栏打开“版本”，选择版本并点击“安装”。请先添加插件。"
                : "添加插件后，在主侧边栏打开“版本”，选择版本并点击“安装”。"
        }
        return "After adding a plugin, open Versions in the main sidebar, choose a version, and click Install."
            + (model.plugins.isEmpty ? " Add a plugin first." : "")
    }

    private var projectDetail: String {
        if model.projects.isEmpty {
            return language == .simplifiedChinese
                ? "在主侧边栏打开“项目”，添加一个包含 .tool-versions 的文件夹。"
                : "Open Projects in the main sidebar and add a folder containing .tool-versions."
        }
        return language == .simplifiedChinese
            ? "已管理 \(model.projects.count) 个项目。"
            : "\(model.projects.count) project\(model.projects.count == 1 ? "" : "s") managed."
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
                Text(language.localized(title)).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let actionTitle, let action {
                    Button(language.localized(actionTitle), action: action)
                        .disabled(model.hasActiveOperation)
                }
            }
            Spacer()
        }
    }
}
