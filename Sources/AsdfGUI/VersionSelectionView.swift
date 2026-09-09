import SwiftUI

private enum VersionSelectionScope: String, CaseIterable, Identifiable {
    case project
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .project: "Project"
        case .home: "Home"
        }
    }
}

private struct PendingVersionSelection {
    let tool: String
    let version: String
    let scope: VersionSelectionScope
    let project: ManagedProject?
}

@MainActor
struct VersionSelectionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var scope: VersionSelectionScope = .project
    @State private var selectedProjectID: String?
    @State private var selectedTool: String?
    @State private var selectedVersion: String?
    @State private var installedVersions: [String] = []
    @State private var isLoadingVersions = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var pendingSelection: PendingVersionSelection?
    @State private var isShowingConfirmation = false

    private var selectedProject: ManagedProject? {
        guard let selectedProjectID else { return nil }
        return model.projects.first(where: { $0.id == selectedProjectID })
    }

    private var versionOptions: [String] {
        var values = installedVersions
        if !values.contains("system") {
            values.append("system")
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set Runtime Version")
                    .font(.title.bold())
                Text("Choose an installed asdf plugin and set an exact project or Home version without editing .tool-versions by hand.")
                    .foregroundStyle(.secondary)
            }

            Picker("Scope", selection: $scope) {
                ForEach(VersionSelectionScope.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Form {
                if scope == .project {
                    Section("Project") {
                        if model.projects.isEmpty {
                            Text("Add a managed project from the Projects screen first.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Project", selection: $selectedProjectID) {
                                ForEach(model.projects) { project in
                                    Text(project.name).tag(Optional(project.id))
                                }
                            }

                            if let project = selectedProject {
                                Text(project.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Section("Runtime") {
                    Picker("Plugin", selection: $selectedTool) {
                        ForEach(model.plugins) { plugin in
                            Text(plugin.name).tag(Optional(plugin.name))
                        }
                    }
                    .disabled(model.plugins.isEmpty)

                    HStack {
                        Picker("Version", selection: $selectedVersion) {
                            ForEach(versionOptions, id: \.self) { version in
                                Text(version).tag(Optional(version))
                            }
                        }
                        .disabled(isLoadingVersions || versionOptions.isEmpty)

                        if isLoadingVersions {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let tool = selectedTool,
                       scope == .project,
                       let project = selectedProject {
                        let current = model.configuredVersions(tool: tool, project: project)
                        LabeledContent(
                            "Current project setting",
                            value: current.isEmpty ? "Not set locally" : current.joined(separator: " → ")
                        )
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if let successMessage {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
            }

            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button("Apply") {
                    prepareConfirmation()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply || isSaving || model.hasActiveOperation)
            }
        }
        .padding(24)
        .frame(width: 620, height: 500)
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = model.projects.first?.id
            }
            if selectedTool == nil {
                selectedTool = model.plugins.first?.name
            }
        }
        .onChange(of: model.projects) { _, projects in
            if let selectedProjectID,
               projects.contains(where: { $0.id == selectedProjectID }) {
                return
            }
            self.selectedProjectID = projects.first?.id
        }
        .onChange(of: model.plugins) { _, plugins in
            if let selectedTool,
               plugins.contains(where: { $0.name == selectedTool }) {
                return
            }
            self.selectedTool = plugins.first?.name
        }
        .task(id: selectedTool) {
            await loadVersions()
        }
        .alert(
            "Change configured version?",
            isPresented: $isShowingConfirmation,
            presenting: pendingSelection
        ) { request in
            Button("Apply") {
                Task { await apply(request) }
            }
            Button("Cancel", role: .cancel) {
                pendingSelection = nil
            }
        } message: { request in
            Text(confirmationMessage(for: request))
        }
    }

    private var canApply: Bool {
        guard selectedTool != nil, selectedVersion != nil else { return false }
        if scope == .project {
            return selectedProject != nil
        }
        return true
    }

    private func loadVersions() async {
        guard let tool = selectedTool else {
            installedVersions = []
            selectedVersion = nil
            return
        }

        isLoadingVersions = true
        errorMessage = nil
        defer { isLoadingVersions = false }

        do {
            let installed = try await model.loadInstalledVersionsForSelection(tool: tool)
            guard !Task.isCancelled, selectedTool == tool else { return }
            installedVersions = installed

            if let selectedVersion, installed.contains(selectedVersion) || selectedVersion == "system" {
                return
            }
            self.selectedVersion = installed.first ?? "system"
        } catch is CancellationError {
            return
        } catch {
            guard selectedTool == tool else { return }
            installedVersions = []
            selectedVersion = "system"
            errorMessage = error.localizedDescription
        }
    }

    private func prepareConfirmation() {
        guard let tool = selectedTool, let version = selectedVersion else { return }
        pendingSelection = PendingVersionSelection(
            tool: tool,
            version: version,
            scope: scope,
            project: scope == .project ? selectedProject : nil
        )
        isShowingConfirmation = true
    }

    private func confirmationMessage(for request: PendingVersionSelection) -> String {
        switch request.scope {
        case .project:
            guard let project = request.project else { return "The selected project is no longer available." }
            let current = model.configuredVersions(tool: request.tool, project: project)
            let currentText = current.isEmpty ? "no local setting" : current.joined(separator: " → ")
            return "This runs asdf set \(request.tool) \(request.version) in \(project.path). The current \(request.tool) project setting is \(currentText). Any existing fallback chain for this tool will be replaced by the selected single version."
        case .home:
            return "This runs asdf set -u \(request.tool) \(request.version) and updates $HOME/.tool-versions. Project-local .tool-versions files continue to override this Home default."
        }
    }

    private func apply(_ request: PendingVersionSelection) async {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer {
            isSaving = false
            pendingSelection = nil
        }

        do {
            switch request.scope {
            case .project:
                guard let project = request.project else {
                    errorMessage = "The selected project is no longer available."
                    return
                }
                try await model.setProjectVersion(
                    tool: request.tool,
                    version: request.version,
                    project: project
                )
                successMessage = "Set \(request.tool) to \(request.version) for \(project.name)."
            case .home:
                try await model.setHomeVersion(tool: request.tool, version: request.version)
                successMessage = "Set Home \(request.tool) version to \(request.version)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
