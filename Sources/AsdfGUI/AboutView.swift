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
                            language.localized("Finish the active asdf operation before installing the app update."),
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
            language.localized("Install update and relaunch?"),
            isPresented: $isShowingInstallConfirmation
        ) {
            Button(language.localized("Install and Relaunch")) {
                do {
                    try updateModel.beginInstallation()
                    NSApplication.shared.terminate(nil)
                } catch {
                    // AppUpdateModel already exposes the launch error in its state.
                }
            }
            Button(language.localized("Cancel"), role: .cancel) {}
        } message: {
            Text(language.localized("asdf GUI will quit briefly, replace the current app with the verified update, and reopen automatically."))
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
            progressRow(language.format("Downloading and verifying %@…", update.version))
            if let size = update.downloadSize {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .readyToInstall(let prepared):
            Label(language.localized("Update downloaded and verified."), systemImage: "checkmark.shield.fill")
                .font(.headline)
            HStack(spacing: 16) {
                LabeledContent(language.localized("Ready to install"), value: prepared.update.version)
                Label(language.localized("SHA-256 verified"), systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            Text(language.localized("The update was verified against the digest published by the official GitHub Release and staged locally. No browser download is required."))
                .font(.caption)
                .foregroundStyle(.secondary)

        case .installing(let version):
            progressRow(language.format("Installing %@ and relaunching…", version))

        case .failed(let message):
            VStack(alignment: .leading, spacing: 5) {
                Label(language.localized("App update failed"), systemImage: "exclamationmark.triangle")
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
            Button(language.localized("Download Update"), systemImage: "arrow.down.circle.fill") {
                Task { await updateModel.downloadAndPrepare() }
            }
            .buttonStyle(.borderedProminent)

        case .readyToInstall:
            Button(language.localized("Install and Relaunch"), systemImage: "arrow.triangle.2.circlepath") {
                isShowingInstallConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(appModel.hasActiveOperation)

        case .failed:
            if updateModel.availableUpdate != nil {
                Button(language.localized("Retry Download"), systemImage: "arrow.clockwise") {
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
        Text(language.localized("Download, verify, install, and relaunch without leaving asdf GUI."))
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

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
