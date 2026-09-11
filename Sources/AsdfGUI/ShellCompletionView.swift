import SwiftUI

@MainActor
struct ShellCompletionView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var model = ShellCompletionModel()
    @State private var isShowingApplyConfirmation = false
    @State private var isShowingRemoveConfirmation = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var isChinese: Bool { language == .simplifiedChinese }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Shell Completions", "Shell 自动补全"))
                        .font(.largeTitle.bold())
                    Text(t(
                        "Configure asdf command completion without manually editing shell files.",
                        "无需手动编辑 Shell 配置文件即可启用 asdf 命令自动补全。"
                    ))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Picker(t("Shell", "Shell"), selection: Binding(
                    get: { model.selectedShell },
                    set: { model.selectShell($0, executableURL: appModel.executableURL) }
                )) {
                    ForEach(SupportedShell.allCases) { shell in
                        Text(shell.displayName).tag(shell)
                    }
                }
                .frame(width: 150)
                .accessibilityHint(Text(t("Choose which shell completion setup to manage.", "选择要管理自动补全的 Shell。")))
            }

            if model.isLoading && model.plan == nil {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(t("Preparing completion preview…", "正在准备自动补全预览…"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let plan = model.plan {
                statusSection(plan)
                previewSection(plan)
                actionRow(plan)

                if plan.status == .configured {
                    Label(
                        t(
                            "Configured. Open a new terminal session for completion changes to take effect.",
                            "已配置。请打开新的终端会话以使自动补全设置生效。"
                        ),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(t("Shell completions configured", "Shell 自动补全已配置")))
                }
            } else {
                ContentUnavailableView(
                    t("Completions unavailable", "自动补全不可用"),
                    systemImage: "text.cursor",
                    description: Text(model.errorMessage ?? t(
                        "Install or select asdf before configuring completions.",
                        "请先安装或选择 asdf，再配置自动补全。"
                    ))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let error = model.errorMessage, model.plan != nil {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text(t("Completion error: \(error)", "自动补全错误：\(error)")))
            }
        }
        .padding(28)
        .frame(minWidth: 760, minHeight: 610)
        .task(id: appModel.executableURL?.path) {
            await model.refresh(executableURL: appModel.executableURL)
        }
        .alert(t("Configure shell completions?", "配置 Shell 自动补全？"), isPresented: $isShowingApplyConfirmation) {
            Button(t("Configure", "配置")) {
                Task { await model.apply(appModel: appModel) }
            }
            Button(t("Cancel", "取消"), role: .cancel) {}
        } message: {
            if let plan = model.plan {
                Text(applyMessage(plan))
            }
        }
        .alert(t("Remove shell completions?", "移除 Shell 自动补全？"), isPresented: $isShowingRemoveConfirmation) {
            Button(t("Remove", "移除"), role: .destructive) {
                Task { await model.remove(appModel: appModel) }
            }
            Button(t("Cancel", "取消"), role: .cancel) {}
        } message: {
            if let plan = model.plan {
                Text(removeMessage(plan))
            }
        }
    }

    @ViewBuilder
    private func statusSection(_ plan: ShellCompletionPlan) -> some View {
        GroupBox(t("Status", "状态")) {
            VStack(alignment: .leading, spacing: 9) {
                LabeledContent(t("Shell", "Shell"), value: plan.shell.displayName)
                LabeledContent(t("Configuration file", "配置文件"), value: plan.configurationURL.path)
                if let completionFileURL = plan.completionFileURL {
                    LabeledContent(t("Generated completion file", "生成的补全文件"), value: completionFileURL.path)
                }
                HStack {
                    Text(t("Completion", "自动补全"))
                    Spacer()
                    Label(statusTitle(plan.status), systemImage: statusSymbol(plan.status))
                }
            }
            .textSelection(.enabled)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(t("Shell completion status", "Shell 自动补全状态")))
    }

    @ViewBuilder
    private func previewSection(_ plan: ShellCompletionPlan) -> some View {
        GroupBox(t("Managed block preview", "托管配置块预览")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(previewExplanation(plan))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(plan.managedBlock)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 115, maxHeight: 180)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))

                if plan.shell == .zsh, let script = plan.proposedCompletionContents {
                    Text(t(
                        "asdf completion zsh produced \(script.split(whereSeparator: { $0.isNewline }).count) lines for the generated _asdf file.",
                        "asdf completion zsh 已为生成的 _asdf 文件产生 \(script.split(whereSeparator: { $0.isNewline }).count) 行内容。"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ plan: ShellCompletionPlan) -> some View {
        HStack {
            Button(t("Refresh Preview", "刷新预览"), systemImage: "arrow.clockwise") {
                Task { await model.refresh(executableURL: appModel.executableURL) }
            }
            .disabled(model.isLoading || model.isApplying || appModel.hasActiveOperation)
            .accessibilityHint(Text(t(
                "Regenerate the preview from current shell files and asdf completion output.",
                "根据当前 Shell 文件和 asdf completion 输出重新生成预览。"
            )))

            Spacer()

            Button(t("Close", "关闭")) { dismiss() }
                .keyboardShortcut(.cancelAction)

            if plan.status != .notConfigured {
                Button(t("Remove Completion", "移除自动补全"), role: .destructive) {
                    isShowingRemoveConfirmation = true
                }
                .disabled(model.isLoading || model.isApplying || appModel.hasActiveOperation)
            }

            if plan.status != .configured {
                Button(
                    plan.status == .needsUpdate
                        ? t("Update Completion", "更新自动补全")
                        : t("Configure Completion", "配置自动补全"),
                    systemImage: "text.cursor"
                ) {
                    isShowingApplyConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isLoading || model.isApplying || appModel.hasActiveOperation)
            }
        }
    }

    private func statusTitle(_ status: ShellCompletionStatus) -> String {
        switch status {
        case .notConfigured: return t("Not configured", "未配置")
        case .configured: return t("Configured", "已配置")
        case .needsUpdate: return t("Update available", "有更新")
        }
    }

    private func statusSymbol(_ status: ShellCompletionStatus) -> String {
        switch status {
        case .notConfigured: return "circle.dashed"
        case .configured: return "checkmark.circle.fill"
        case .needsUpdate: return "arrow.triangle.2.circlepath.circle"
        }
    }

    private func previewExplanation(_ plan: ShellCompletionPlan) -> String {
        if plan.shell == .bash {
            return t(
                "asdf GUI manages only the marked block below in .bashrc. It uses the selected asdf executable to generate Bash completions when a shell starts. On macOS, make sure your Bash login profile sources .bashrc if your setup requires it.",
                "asdf GUI 只管理 .bashrc 中下方带标记的配置块，并在 Shell 启动时使用当前选定的 asdf 可执行文件生成 Bash 补全。在 macOS 上，如果你的 Bash 登录配置需要显式加载 .bashrc，请确保已正确 source。"
            )
        }
        return t(
            "asdf GUI manages only the marked fpath/compinit block below. The _asdf file is generated from the current `asdf completion zsh` output.",
            "asdf GUI 只管理下方带标记的 fpath/compinit 配置块；_asdf 文件由当前 `asdf completion zsh` 输出生成。"
        )
    }

    private func applyMessage(_ plan: ShellCompletionPlan) -> String {
        if plan.shell == .zsh, let completionFileURL = plan.completionFileURL {
            return t(
                "asdf GUI will update only its marked block in \(plan.configurationURL.path) and write the generated completion script to \(completionFileURL.path). Both files are checked for external changes before writing.",
                "asdf GUI 只会更新 \(plan.configurationURL.path) 中自己的标记配置块，并把生成的补全脚本写入 \(completionFileURL.path)。写入前会检查两个文件是否被外部修改。"
            )
        }
        return t(
            "asdf GUI will update only its marked completion block in \(plan.configurationURL.path). Existing content outside the markers remains unchanged.",
            "asdf GUI 只会更新 \(plan.configurationURL.path) 中自己的自动补全标记块，标记之外的现有内容保持不变。"
        )
    }

    private func removeMessage(_ plan: ShellCompletionPlan) -> String {
        if plan.shell == .zsh {
            return t(
                "Only the asdf GUI completion block will be removed from \(plan.configurationURL.path). The generated _asdf file is intentionally retained to avoid deleting a file another shell framework may also use.",
                "只会从 \(plan.configurationURL.path) 移除 asdf GUI 的自动补全配置块。生成的 _asdf 文件会保留，避免误删其他 Shell 框架也可能使用的文件。"
            )
        }
        return t(
            "Only the asdf GUI completion block will be removed from \(plan.configurationURL.path).",
            "只会从 \(plan.configurationURL.path) 中移除 asdf GUI 的自动补全配置块。"
        )
    }

    private func t(_ english: String, _ chinese: String) -> String {
        isChinese ? chinese : english
    }
}
