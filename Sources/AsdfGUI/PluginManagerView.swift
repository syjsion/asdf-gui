import SwiftUI

@MainActor
struct PluginManagerView: View {
    @Environment(AppModel.self) private var appModel
    @State private var state = PluginManagementModel()
    @State private var isAddingPlugin = false
    @State private var pluginName = ""
    @State private var pluginURL = ""

    var body: some View {
        @Bindable var state = state

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Plugin Manager").font(.largeTitle.bold())
                    Text("Add, update, and safely remove asdf plugins.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if state.isPreparingRemoval {
                    ProgressView().controlSize(.small)
                }
                Button("Add Plugin", systemImage: "plus") {
                    pluginName = ""
                    pluginURL = ""
                    isAddingPlugin = true
                }
                .disabled(state.isBusy || appModel.hasActiveOperation)
                Button("Update All", systemImage: "arrow.triangle.2.circlepath") {
                    state.updateAllPlugins(appModel: appModel)
                }
                .disabled(state.isBusy || appModel.hasActiveOperation || appModel.plugins.isEmpty)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await appModel.refresh() }
                }
                .disabled(state.isBusy)
            }

            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if let operation = state.activeOperation {
                PluginOperationPanel(state: state, operation: operation)
            }

            if appModel.plugins.isEmpty && !appModel.isLoading {
                ContentUnavailableView(
                    "No plugins installed",
                    systemImage: "shippingbox",
                    description: Text("Add a plugin by short name or, preferably, by its Git URL.")
                )
            } else {
                Table(appModel.plugins) {
                    TableColumn("Plugin") { plugin in
                        Text(plugin.name).fontWeight(.medium)
                    }
                    TableColumn("Repository") { plugin in
                        Text(plugin.url ?? "Short-name repository")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    TableColumn("Actions") { plugin in
                        HStack(spacing: 10) {
                            Button("Update") {
                                state.updatePlugin(plugin, appModel: appModel)
                            }
                            .buttonStyle(.borderless)
                            .disabled(state.isBusy || appModel.hasActiveOperation)

                            Button("Remove", role: .destructive) {
                                Task { await state.prepareRemoval(of: plugin, appModel: appModel) }
                            }
                            .buttonStyle(.borderless)
                            .disabled(state.isBusy || appModel.hasActiveOperation)
                        }
                    }
                }
            }
        }
        .padding(24)
        .sheet(isPresented: $isAddingPlugin) {
            addPluginSheet
        }
        .sheet(item: $state.removalImpact) { impact in
            PluginRemovalConfirmationView(
                impact: impact,
                onCancel: { state.cancelRemoval() },
                onConfirm: { state.confirmRemoval(appModel: appModel) }
            )
        }
        .onDisappear {
            state.cancelOperation()
        }
    }

    private var addPluginSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Plugin").font(.title2.bold())

            Form {
                TextField("Plugin name", text: $pluginName, prompt: Text("nodejs"))
                TextField("Git URL (recommended)", text: $pluginURL, prompt: Text("https://github.com/asdf-vm/asdf-nodejs.git"))
            }
            .formStyle(.grouped)

            Text("Leaving Git URL empty uses asdf's short-name repository. A Git URL is more explicit and independent of that index.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { isAddingPlugin = false }
                Button("Add") {
                    state.addPlugin(
                        name: pluginName,
                        gitURL: pluginURL.isEmpty ? nil : pluginURL,
                        appModel: appModel
                    )
                    isAddingPlugin = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pluginName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private struct PluginOperationPanel: View {
    let state: PluginManagementModel
    let operation: PluginOperationTaskState

    var body: some View {
        GroupBox("Plugin Task") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(operationTitle, systemImage: operationSymbol)
                        .font(.headline)
                    Spacer()
                    if operation.isRunning {
                        Button("Cancel", role: .destructive) { state.cancelOperation() }
                    } else {
                        Button("Close") { state.dismissOperation() }
                    }
                }

                if let error = operation.errorMessage {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }

                ScrollView {
                    Text(operation.log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 90, maxHeight: 180)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var operationTitle: String {
        switch operation.status {
        case .running: "\(operation.kind.verb) in progress"
        case .succeeded: "Plugin operation complete"
        case .failed: "Plugin operation failed"
        case .cancelled: "Plugin operation cancelled"
        }
    }

    private var operationSymbol: String {
        switch operation.status {
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }
}

private struct PluginRemovalConfirmationView: View {
    let impact: PluginRemovalImpact
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Remove \(impact.plugin.name)?", systemImage: "exclamationmark.triangle.fill")
                .font(.title2.bold())

            Text("asdf will remove the plugin and every runtime version installed through it. This cannot be undone without reinstalling the plugin and runtimes.")

            GroupBox("Installed versions to remove") {
                if impact.installedVersions.isEmpty {
                    Text("No installed runtime versions were reported.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(impact.installedVersions, id: \.self) { version in
                            Text("• \(version)").font(.system(.body, design: .monospaced))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Managed project impact") {
                if impact.projects.isEmpty {
                    Text("No managed project currently references this plugin.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(impact.projects) { project in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(project.name).fontWeight(.medium)
                                Text(project.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !impact.projects.isEmpty {
                Text("Those projects will report the tool as Plugin missing after removal. Their .tool-versions files will not be changed.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Remove Plugin", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 600)
    }
}
