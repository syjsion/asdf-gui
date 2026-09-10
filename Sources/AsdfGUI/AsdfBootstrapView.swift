import SwiftUI

struct RootContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(AsdfBootstrapModel.self) private var bootstrap

    var body: some View {
        Group {
            if model.isLoading && model.executableURL == nil && bootstrap.activeInstallation == nil {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Checking for asdf…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.executableURL == nil {
                AsdfSetupView()
            } else {
                ContentView()
            }
        }
        .task {
            if model.executableURL == nil {
                await model.refresh()
            }
        }
    }
}

struct AsdfSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(AsdfBootstrapModel.self) private var bootstrap

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("asdf is required", systemImage: "shippingbox.and.arrow.backward")
                        .font(.largeTitle.bold())
                    Text("asdf GUI could not find a usable asdf executable on this Mac.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                GroupBox("Install from the official asdf release") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Downloads the latest stable macOS archive from asdf-vm/asdf on GitHub.", systemImage: "arrow.down.circle")
                        Label("Selects Apple Silicon or Intel automatically for this app build.", systemImage: "cpu")
                        Label("Requires the release asset SHA-256 digest and verifies it before extraction.", systemImage: "checkmark.shield")
                        Label("Installs only to ~/.local/bin/asdf. No sudo and no Homebrew are required.", systemImage: "folder")
                        Label("Does not edit ~/.zshrc or other shell configuration files.", systemImage: "doc.text")

                        HStack {
                            Button("Install asdf", systemImage: "arrow.down.circle.fill") {
                                bootstrap.install(appModel: model)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(bootstrap.isInstalling || model.hasActiveOperation && !bootstrap.isInstalling)

                            Button("Refresh Detection", systemImage: "arrow.clockwise") {
                                Task { await model.refresh() }
                            }
                            .disabled(bootstrap.isInstalling)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if let task = bootstrap.activeInstallation {
                    AsdfInstallationPanel(task: task)
                }

                GroupBox("Already installed somewhere else?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open Settings and use “Choose asdf…” to select an existing executable. Automatic detection checks common Homebrew locations, ~/.local/bin, and ~/go/bin.")
                            .foregroundStyle(.secondary)
                        Text("After a GUI-managed install, asdf GUI remembers ~/.local/bin/asdf directly, so Finder-launched apps do not depend on your interactive shell PATH.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = model.errorMessage, bootstrap.activeInstallation?.isRunning != true {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
    }
}

struct AsdfInstallationPanel: View {
    @Environment(AsdfBootstrapModel.self) private var bootstrap
    let task: AsdfInstallationTaskState

    var body: some View {
        GroupBox("asdf Installation") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(task.status.title, systemImage: task.status.symbolName)
                        .font(.headline)
                    Spacer()
                    if task.isRunning {
                        Button("Cancel", role: .destructive) {
                            bootstrap.cancel()
                        }
                    } else {
                        Button("Close") {
                            bootstrap.dismiss()
                        }
                    }
                }

                if let destination = task.destination {
                    LabeledContent("Installed at", value: destination.path)
                        .font(.callout)
                }
                if let version = task.version {
                    LabeledContent("Detected version", value: version)
                        .font(.callout)
                }
                if let error = task.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .textSelection(.enabled)
                }

                ScrollView {
                    Text(task.log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

private extension AsdfInstallationStatus {
    var title: String {
        switch self {
        case .running: "Installing asdf"
        case .succeeded: "asdf is ready"
        case .failed: "Installation failed"
        case .cancelled: "Installation cancelled"
        }
    }

    var symbolName: String {
        switch self {
        case .running: "arrow.down.circle"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }
}
