import AppKit
import SwiftUI

@MainActor
struct AboutView: View {
    @Environment(AppModel.self) private var appModel
    @State private var updateModel = AppUpdateModel()
    @State private var isShowingInstallConfirmation = false
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 18) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 82, height: 82)
                    .shadow(radius: 4, y: 2)

                VStack(alignment: .leading, spacing: 5) {
                    Text("asdf GUI")
                        .font(.largeTitle.bold())
                    Text("Native macOS GUI for asdf, built with SwiftUI.")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Text("\(language.localized("Version")) \(AppBuildInfo.version)")
                        Text("\(language.localized("Build")) \(AppBuildInfo.build)")
                    }
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }

            GroupBox("About asdf GUI") {
                VStack(alignment: .leading, spacing: 9) {
                    LabeledContent("Current app version", value: AppBuildInfo.version)
                    LabeledContent("asdf", value: appModel.asdfVersion)
                    if let executable = appModel.executableURL {
                        LabeledContent("asdf executable", value: executable.path)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("Project on GitHub", systemImage: "link") {
                            open(URL(string: "https://github.com/syjsion/asdf-gui")!)
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(language.localized("Check for Updates")) {
                VStack(alignment: .leading, spacing: 12) {
                    updateStatus

                    if appModel.hasActiveOperation,
                       case .readyToInstall = updateModel.state {
                        Label(
                            tr("Finish the active asdf operation before installing the app update.", "请先完成当前 asdf 操作，再安装应用更新。"),
                            systemImage: "hourglass"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button(language.localized("Check for Updates"), systemImage: "arrow.clockwise") {
                            Task { await updateModel.check() }
                        }
                        .disabled(updateModel.isBusy)

                        Spacer()
                        updateActions
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
        .frame(width: 640, height: 560)
        .task {
            if case .idle = updateModel.state {
                await updateModel.check()
            }
        }
        .alert(
            tr("Install update and relaunch?", "安装更新并重新启动？"),
            isPresented: $isShowingInstallConfirmation
        ) {
            Button(tr("Install and Relaunch", "安装并重新启动")) {
                do {
                    try updateModel.beginInstallation()
                    NSApplication.shared.terminate(nil)
                } catch {
                    // AppUpdateModel already exposes the launch error in its state.
                }
            }
            Button(language.localized("Cancel"), role: .cancel) {}
        } message: {
            Text(tr(
                "asdf GUI will quit briefly, replace the current app with the verified update, and reopen automatically.",
                "asdf GUI 会短暂退出，用已验证的更新替换当前应用，然后自动重新打开。"
            ))
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateModel.state {
        case .idle:
            Text(language.localized("Check for Updates"))
                .foregroundStyle(.secondary)
        case .checking:
            progressRow(language.localized("Checking for updates…"))
        case .upToDate(let latestVersion):
            Label(language.localized("You're up to date."), systemImage: "checkmark.circle.fill")
            if let latestVersion {
                LabeledContent(language.localized("Latest release"), value: latestVersion)
                    .font(.callout)
            }
        case .updateAvailable(let update):
            updateAvailableStatus(update)
        case .downloading(let update):
            progressRow(language == .simplifiedChinese
                ? "正在下载并验证 \(update.version)…"
                : "Downloading and verifying \(update.version)…")
            if let size = update.downloadSize {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .readyToInstall(let prepared):
            Label(tr("Update downloaded and verified.", "更新已下载并验证。"), systemImage: "checkmark.shield.fill")
                .font(.headline)
            HStack(spacing: 16) {
                LabeledContent(tr("Ready to install", "准备安装"), value: prepared.update.version)
                Label(tr("SHA-256 verified", "SHA-256 已验证"), systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Text(tr(
                "The update was verified against the digest published by the official GitHub Release and staged locally. No browser download is required.",
                "更新已根据官方 GitHub Release 发布的摘要完成校验并暂存到本机，无需再通过浏览器下载。"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        case .installing(let version):
            progressRow(language == .simplifiedChinese
                ? "正在安装 \(version) 并重新启动…"
                : "Installing \(version) and relaunching…")
        case .failed(let message):
            VStack(alignment: .leading, spacing: 5) {
                Label(tr("App update failed", "应用更新失败"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var updateActions: some View {
        switch updateModel.state {
        case .updateAvailable:
            Button(tr("Download Update", "下载更新"), systemImage: "arrow.down.circle.fill") {
                Task { await updateModel.downloadAndPrepare() }
            }
            .buttonStyle(.borderedProminent)
        case .readyToInstall:
            Button(tr("Install and Relaunch", "安装并重新启动"), systemImage: "arrow.triangle.2.circlepath") {
                isShowingInstallConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.hasActiveOperation)
        case .failed:
            if updateModel.availableUpdate != nil {
                Button(tr("Retry Download", "重新下载"), systemImage: "arrow.clockwise") {
                    Task { await updateModel.downloadAndPrepare() }
                }
            }
        case .idle, .checking, .upToDate, .downloading, .installing:
            EmptyView()
        }

        if let update = updateModel.availableUpdate {
            Button(language.localized("Open Release Page"), systemImage: "safari") {
                open(update.releaseURL)
            }
        }
    }

    @ViewBuilder
    private func updateAvailableStatus(_ update: AvailableAppUpdate) -> some View {
        Label(language.localized("A newer version is available."), systemImage: "arrow.down.circle.fill")
            .font(.headline)
        HStack(spacing: 16) {
            LabeledContent(language.localized("Latest release"), value: update.version)
            if update.prerelease {
                Label(language.localized("Prerelease"), systemImage: "testtube.2")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        Text(tr(
            "Download, verify, install, and relaunch without leaving asdf GUI.",
            "无需离开 asdf GUI，即可完成下载、验证、安装和重新启动。"
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private func tr(_ english: String, _ simplifiedChinese: String) -> String {
        language == .simplifiedChinese ? simplifiedChinese : english
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
