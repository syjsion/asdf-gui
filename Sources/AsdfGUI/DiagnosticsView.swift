import AppKit
import SwiftUI

@MainActor
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var state = DiagnosticsModel()
    @State private var selectedTool: String?
    @State private var selectedVersion = ""
    @State private var commandName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diagnostics").font(.largeTitle.bold())
                    Text("Inspect paths, shims, and environment information without remembering asdf commands.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if state.isRunning {
                    ProgressView().controlSize(.small)
                }
            }

            Picker("Diagnostic", selection: $state.action) {
                ForEach(DiagnosticAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.segmented)

            GroupBox {
                diagnosticControls
            } label: {
                Text(state.action.commandSummary)
                    .font(.system(.callout, design: .monospaced))
            }

            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            if let error = state.versionsError {
                Text("Installed versions: \(error)")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(state.outputTitle).font(.headline)
                        Spacer()
                        Button("Copy Output", systemImage: "doc.on.doc") {
                            copyToPasteboard(state.output)
                        }
                        .disabled(state.output.isEmpty)
                        Button("Copy Diagnostic Report", systemImage: "stethoscope") {
                            Task {
                                do {
                                    let report = try await state.diagnosticReport(appModel: appModel)
                                    copyToPasteboard(report)
                                } catch {
                                    state.errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .disabled(state.isRunning || appModel.executableURL == nil)
                    }

                    ScrollView {
                        Text(state.output.isEmpty ? "Run a diagnostic to see its output here." : state.output)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(state.output.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)
                    }
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                }
            } label: {
                Text("Output")
            }
        }
        .padding(24)
        .task {
            if appModel.executableURL == nil {
                await appModel.refresh()
            }
            if selectedTool == nil {
                selectedTool = appModel.plugins.first?.name
            }
        }
        .onChange(of: appModel.plugins) { _, plugins in
            if let selectedTool, plugins.contains(where: { $0.name == selectedTool }) {
                return
            }
            selectedTool = plugins.first?.name
        }
        .task(id: selectedTool) {
            selectedVersion = ""
            await state.loadInstalledVersions(tool: selectedTool, appModel: appModel)
        }
    }

    @ViewBuilder
    private var diagnosticControls: some View {
        switch state.action {
        case .info:
            HStack {
                Text("Print OS, shell, and asdf debug information.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Run Info", systemImage: "play.fill") {
                    Task { await state.runInfo(appModel: appModel) }
                }
                .disabled(state.isRunning || appModel.executableURL == nil)
            }

        case .wherePath:
            HStack {
                toolPicker
                Picker("Version", selection: $selectedVersion) {
                    Text("Current").tag("")
                    ForEach(state.installedVersions, id: \.self) { version in
                        Text(version).tag(version)
                    }
                }
                .frame(maxWidth: 230)
                Spacer()
                Button("Find Install Path", systemImage: "folder") {
                    guard let selectedTool else { return }
                    Task {
                        await state.runWhere(
                            tool: selectedTool,
                            version: selectedVersion.isEmpty ? nil : selectedVersion,
                            appModel: appModel
                        )
                    }
                }
                .disabled(state.isRunning || selectedTool == nil)
            }

        case .which:
            HStack {
                TextField("Command", text: $commandName, prompt: Text("node, npm, python…"))
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Button("Resolve Executable", systemImage: "arrow.right.square") {
                    Task { await state.runWhich(command: commandName, appModel: appModel) }
                }
                .disabled(state.isRunning || commandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

        case .reshim:
            HStack {
                toolPicker
                Picker("Version", selection: $selectedVersion) {
                    if state.installedVersions.isEmpty {
                        Text("No installed versions").tag("")
                    }
                    ForEach(state.installedVersions, id: \.self) { version in
                        Text(version).tag(version)
                    }
                }
                .frame(maxWidth: 230)
                Spacer()
                Button("Reshim", systemImage: "arrow.triangle.2.circlepath") {
                    guard let selectedTool, !selectedVersion.isEmpty else { return }
                    Task { await state.runReshim(tool: selectedTool, version: selectedVersion, appModel: appModel) }
                }
                .disabled(state.isRunning || appModel.hasActiveOperation || selectedTool == nil || selectedVersion.isEmpty)
            }
        }
    }

    private var toolPicker: some View {
        Picker("Tool", selection: $selectedTool) {
            if appModel.plugins.isEmpty {
                Text("No plugins").tag(String?.none)
            }
            ForEach(appModel.plugins) { plugin in
                Text(plugin.name).tag(String?.some(plugin.name))
            }
        }
        .frame(maxWidth: 240)
    }

    private func copyToPasteboard(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
