import AppKit
import SwiftUI

@MainActor
struct AboutView: View {
    @Environment(AppModel.self) private var appModel
    @State private var updateModel = AppUpdateModel()
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

            GroupBox("Check for Updates") {
                VStack(alignment: .leading, spacing: 12) {
                    updateStatus

                    HStack {
                        Button("Check for Updates", systemImage: "arrow.clockwise") {
                            Task { await updateModel.check() }
                        }
                        .disabled(updateModel.isChecking)

                        Spacer()

                        if case .updateAvailable(let update) = updateModel.state {
                            if let downloadURL = update.downloadURL {
                                Button("Download Update", systemImage: "arrow.down.circle.fill") {
                                    open(downloadURL)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            Button("Open Release Page", systemImage: "safari") {
                                open(update.releaseURL)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(28)
        .frame(width: 600, height: 500)
        .task {
            if case .idle = updateModel.state {
                await updateModel.check()
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateModel.state {
        case .idle:
            Text("Check for Updates")
                .foregroundStyle(.secondary)

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
                    .foregroundStyle(.secondary)
            }

        case .upToDate(let latestVersion):
            Label("You're up to date.", systemImage: "checkmark.circle.fill")
            if let latestVersion {
                LabeledContent("Latest release", value: latestVersion)
                    .font(.callout)
            }

        case .updateAvailable(let update):
            Label("A newer version is available.", systemImage: "arrow.down.circle.fill")
                .font(.headline)
            HStack(spacing: 16) {
                LabeledContent("Latest release", value: update.version)
                if update.prerelease {
                    Label("Prerelease", systemImage: "testtube.2")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

        case .failed(let message):
            VStack(alignment: .leading, spacing: 5) {
                Label("Update check failed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
