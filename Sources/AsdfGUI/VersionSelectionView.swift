import SwiftUI

private enum VersionSelectionScope: String, CaseIterable, Identifiable {
    case project
    case parent
    case home

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .project: language.localized("Project")
        case .parent: language.localized("Parent")
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
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

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

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var selectedProject: ManagedProject? {
        guard let selectedProjectID else { return nil }
        return model.projects.first(where: { $0.id == selectedProjectID })
    }

    private var parentFile: URL? {
        guard let selectedProject else { return nil }
        return model.parentToolVersionsFile(for: selectedProject)
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
                Text(language.localized("Choose where the exact version should be written: this project, the closest parent configuration, or Home."))
                    .foregroundStyle(.secondary)
            }

            Picker(language.localized("Scope"), selection: $scope) {
                ForEach(VersionSelectionScope.allCases) { item in
                    Text(item.title(language: language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 390)

            Form {
                if scope != .home {
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

                            if scope == .parent {
                                if let parentFile {
                                    LabeledContent(language.localized("Parent configuration")) {
                                        Text(parentFile.path)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    }
                                } else if selectedProject != nil {
                                    Label(
                                        language.localized("No parent .tool-versions file exists above this project."),
                                        systemImage: "exclamationmark.triangle"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                }
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
                            value: current.isEmpty ? language.localized("Not set locally") : current.joined(separator: " → ")
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
                Button("Apply") { prepareConfirmation() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canApply || isSaving || model.hasActiveOperation)
            }
        }
        .padding(24)
        .frame(width: 680, height: 560)
        .onAppear {
            if selectedProjectID == nil { selectedProjectID = model.projects.first?.id }
            if selectedTool == nil { selectedTool = model.plugins.first?.name }
        }
        .onChange(of: model.projects) { _, projects in
            if let selectedProjectID, projects.contains(where: { $0.id == selectedProjectID }) { return }
            self.selectedProjectID = projects.first?.id
        }
        .onChange(of: model.plugins) { _, plugins in
            if let selectedTool, plugins.contains(where: { $0.name == selectedTool }) { return }
            self.selectedTool = plugins.first?.name
        }
        .task(id: selectedTool) { await loadVersions() }
        .alert(
            language.localized("Change configured version?"),
            isPresented: $isShowingConfirmation,
            presenting: pendingSelection
        ) { request in
            Button("Apply") { Task { await apply(request) } }
            Button("Cancel", role: .cancel) { pendingSelection = nil }
        } message: { request in
            Text(confirmationMessage(for: request))
        }
    }

    private var canApply: Bool {
        guard selectedTool != nil, selectedVersion != nil else { return false }
        switch scope {
        case .project: return selectedProject != nil
        case .parent: return selectedProject != nil && parentFile != nil
        case .home: return true
        }
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
            if let selectedVersion, installed.contains(selectedVersion) || selectedVersion == "system" { return }
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
            project: scope == .home ? nil : selectedProject
        )
        isShowingConfirmation = true
    }

    private func confirmationMessage(for request: PendingVersionSelection) -> String {
        if language == .simplifiedChinese {
            switch request.scope {
            case .project:
                guard let project = request.project else { return "所选项目已不可用。" }
                let current = model.configuredVersions(tool: request.tool, project: project)
                let currentText = current.isEmpty ? "没有本地设置" : current.joined(separator: " → ")
                return "将在 \(project.path) 中执行 asdf set \(request.tool) \(request.version)。当前设置为 \(currentText)，现有 fallback 链会被这个单一版本替换。"
            case .parent:
                guard let project = request.project, let file = model.parentToolVersionsFile(for: project) else {
                    return "没有可用的父级 .tool-versions。"
                }
                return "将在项目目录中执行 asdf set -p \(request.tool) \(request.version)，asdf 会修改最近的父级配置：\(file.path)。项目自己的 .tool-versions（如果存在）仍然拥有更高优先级。"
            case .home:
                return "将执行 asdf set -u \(request.tool) \(request.version) 并更新 $HOME/.tool-versions。项目和父级配置仍会覆盖 Home 默认值。"
            }
        }

        switch request.scope {
        case .project:
            guard let project = request.project else { return "The selected project is no longer available." }
            let current = model.configuredVersions(tool: request.tool, project: project)
            let currentText = current.isEmpty ? "no local setting" : current.joined(separator: " → ")
            return "This runs asdf set \(request.tool) \(request.version) in \(project.path). The current project setting is \(currentText). Any existing fallback chain for this tool will be replaced by the selected single version."
        case .parent:
            guard let project = request.project, let file = model.parentToolVersionsFile(for: project) else {
                return "No parent .tool-versions file is available."
            }
            return "This runs asdf set -p \(request.tool) \(request.version) from the project directory. asdf will update the closest parent configuration at \(file.path). A project-local .tool-versions file, when present, still has higher precedence."
        case .home:
            return "This runs asdf set -u \(request.tool) \(request.version) and updates $HOME/.tool-versions. Project and parent configurations continue to override this Home default."
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
                    errorMessage = language.localized("The selected project is no longer available.")
                    return
                }
                try await model.setProjectVersion(tool: request.tool, version: request.version, project: project)
                successMessage = language == .simplifiedChinese
                    ? "已将 \(project.name) 的 \(request.tool) 设置为 \(request.version)。"
                    : "Set \(request.tool) to \(request.version) for \(project.name)."
            case .parent:
                guard let project = request.project else {
                    errorMessage = language.localized("The selected project is no longer available.")
                    return
                }
                try await model.setParentVersion(tool: request.tool, version: request.version, project: project)
                successMessage = language == .simplifiedChinese
                    ? "已将最近父级的 \(request.tool) 设置为 \(request.version)。"
                    : "Set the closest parent \(request.tool) version to \(request.version)."
            case .home:
                try await model.setHomeVersion(tool: request.tool, version: request.version)
                successMessage = language == .simplifiedChinese
                    ? "已将 Home 的 \(request.tool) 设置为 \(request.version)。"
                    : "Set Home \(request.tool) version to \(request.version)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
