import SwiftUI

private struct ProjectToolVersionsEditorRequest: Identifiable {
    let id = UUID()
    let requirement: ToolRequirement?
}

@MainActor
struct ProjectToolVersionsManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    let project: ManagedProject

    @State private var editorRequest: ProjectToolVersionsEditorRequest?
    @State private var pendingRemoval: ToolRequirement?
    @State private var isShowingRemovalConfirmation = false
    @State private var isRemoving = false
    @State private var errorMessage: String?

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var snapshot: ProjectSnapshot? {
        model.projectSnapshots.first(where: { $0.project.id == project.id })
    }

    private var existingToolNames: Set<String> {
        Set(snapshot?.requirements.map(\.tool) ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage .tool-versions")
                        .font(.largeTitle.bold())
                    Text(project.name)
                        .font(.title3.weight(.medium))
                    Text(project.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Button("Close") { dismiss() }
            }

            GroupBox("How changes are applied") {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Add and edit actions use asdf set in this project directory.", systemImage: "terminal")
                    Label("Fallback versions are stored in the order shown below.", systemImage: "arrow.down")
                    Label("asdf has no command to delete one tool entry, so removal is a guarded line-level exception that preserves every other line and comment.", systemImage: "checkmark.shield")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            if let snapshot {
                if let snapshotError = snapshot.errorMessage {
                    ContentUnavailableView(
                        "Project configuration unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(snapshotError)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    configurationContent(snapshot)
                }
            } else {
                ContentUnavailableView(
                    "Project unavailable",
                    systemImage: "folder.badge.questionmark",
                    description: Text("The project is no longer in the managed-project list.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(26)
        .frame(minWidth: 760, minHeight: 580)
        .sheet(item: $editorRequest) { request in
            ProjectToolVersionsEditorView(
                project: project,
                existingRequirement: request.requirement,
                existingToolNames: existingToolNames
            )
        }
        .alert(
            "Remove tool from .tool-versions?",
            isPresented: $isShowingRemovalConfirmation,
            presenting: pendingRemoval
        ) { requirement in
            Button("Remove", role: .destructive) {
                Task { await remove(requirement) }
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: { requirement in
            Text(removalMessage(requirement))
        }
    }

    @ViewBuilder
    private func configurationContent(_ snapshot: ProjectSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Configured tools")
                        .font(.title3.bold())
                    Text(snapshot.hasToolVersionsFile ? ".tool-versions" : "The file will be created by asdf when you add the first tool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isRemoving {
                    ProgressView().controlSize(.small)
                }
                Button("Add Tool", systemImage: "plus") {
                    errorMessage = nil
                    editorRequest = ProjectToolVersionsEditorRequest(requirement: nil)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.hasActiveOperation || isRemoving)
            }

            if snapshot.requirements.isEmpty {
                ContentUnavailableView(
                    snapshot.hasToolVersionsFile ? "No tool entries" : "No .tool-versions yet",
                    systemImage: "doc.badge.plus",
                    description: Text("Add a tool and choose one or more versions. asdf GUI will write the configuration through asdf set.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(snapshot.requirements.enumerated()), id: \.offset) { _, requirement in
                            configuredToolRow(requirement)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func configuredToolRow(_ requirement: ToolRequirement) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Label(requirement.tool, systemImage: "shippingbox")
                        .font(.headline)

                    HStack(spacing: 7) {
                        ForEach(Array(requirement.versions.enumerated()), id: \.offset) { index, version in
                            Text(version)
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                            if index < requirement.versions.count - 1 {
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Text(fallbackSummary(requirement))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 18)

                HStack(spacing: 10) {
                    Button("Edit", systemImage: "slider.horizontal.3") {
                        errorMessage = nil
                        editorRequest = ProjectToolVersionsEditorRequest(requirement: requirement)
                    }
                    .disabled(model.hasActiveOperation || isRemoving)

                    Button("Remove", systemImage: "trash", role: .destructive) {
                        pendingRemoval = requirement
                        isShowingRemovalConfirmation = true
                    }
                    .disabled(model.hasActiveOperation || isRemoving)
                }
            }
            .padding(3)
        }
    }

    private func fallbackSummary(_ requirement: ToolRequirement) -> String {
        if language == .simplifiedChinese {
            return requirement.versions.count == 1
                ? "主版本：\(requirement.versions[0])"
                : "按从左到右的顺序尝试 \(requirement.versions.count) 个版本"
        }
        return requirement.versions.count == 1
            ? "Primary version: \(requirement.versions[0])"
            : "\(requirement.versions.count) versions are tried from left to right"
    }

    private func removalMessage(_ requirement: ToolRequirement) -> String {
        let versions = requirement.versions.joined(separator: " → ")
        if language == .simplifiedChinese {
            return "将从此项目的 .tool-versions 中移除 \(requirement.tool)（\(versions)）。asdf 0.20 没有删除单个工具条目的命令，因此这是唯一一个由 asdf GUI 直接执行的受控文件修改；只会删除该工具对应的一行，并保留其他内容和注释。"
        }
        return "This removes \(requirement.tool) (\(versions)) from this project's .tool-versions. asdf 0.20 has no command for deleting one tool entry, so this is the only guarded direct file mutation: asdf GUI removes exactly that tool line and preserves all other content and comments."
    }

    private func remove(_ requirement: ToolRequirement) async {
        isRemoving = true
        errorMessage = nil
        defer {
            isRemoving = false
            pendingRemoval = nil
        }

        do {
            try await model.removeProjectToolRequirement(
                project: project,
                tool: requirement.tool,
                expectedVersions: requirement.versions
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
private struct ProjectToolVersionsEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    let project: ManagedProject
    let existingRequirement: ToolRequirement?
    let existingToolNames: Set<String>

    @State private var selectedTool: String
    @State private var selectedVersions: [String]
    @State private var manualVersion = ""
    @State private var searchText = ""
    @State private var catalog: ProjectToolVersionCatalog?
    @State private var isLoadingCatalog = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        project: ManagedProject,
        existingRequirement: ToolRequirement?,
        existingToolNames: Set<String>
    ) {
        self.project = project
        self.existingRequirement = existingRequirement
        self.existingToolNames = existingToolNames
        _selectedTool = State(initialValue: existingRequirement?.tool ?? "")
        _selectedVersions = State(initialValue: existingRequirement?.versions ?? [])
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var normalizedTool: String {
        selectedTool.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isInstalledPlugin: Bool {
        model.plugins.contains(where: { $0.name == normalizedTool })
    }

    private var filteredRecords: [ToolVersionRecord] {
        guard let catalog else { return [] }
        let selected = Set(selectedVersions)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.records.filter { record in
            !selected.contains(record.version)
                && (query.isEmpty || record.version.localizedCaseInsensitiveContains(query))
        }
    }

    private var canSave: Bool {
        guard !normalizedTool.isEmpty, !selectedVersions.isEmpty, !isSaving else { return false }
        guard normalizedTool.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        if existingRequirement == nil && existingToolNames.contains(normalizedTool) {
            return false
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(existingRequirement == nil ? "Add tool configuration" : "Edit tool configuration")
                        .font(.title.bold())
                    Text(project.name)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoadingCatalog || isSaving {
                    ProgressView().controlSize(.small)
                }
            }

            GroupBox("Tool") {
                VStack(alignment: .leading, spacing: 10) {
                    if existingRequirement == nil {
                        HStack {
                            TextField("Tool name", text: $selectedTool, prompt: Text("nodejs, python, ruby…"))
                                .textFieldStyle(.roundedBorder)

                            Menu("Installed Plugins") {
                                ForEach(model.plugins) { plugin in
                                    Button(plugin.name) {
                                        selectedTool = plugin.name
                                    }
                                    .disabled(existingToolNames.contains(plugin.name))
                                }
                            }
                        }
                        Text("Choose an installed plugin or enter a tool name. Existing project entries cannot be duplicated.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Tool", value: normalizedTool)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Fallback chain") {
                VStack(alignment: .leading, spacing: 10) {
                    if selectedVersions.isEmpty {
                        Text("Add at least one version. The first item is the primary version; later items are fallbacks.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(selectedVersions.enumerated()), id: \.offset) { index, version in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(version)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                if catalog?.installed.contains(version) == true {
                                    Label("Installed", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    moveVersion(at: index, offset: -1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                .help("Move earlier")

                                Button {
                                    moveVersion(at: index, offset: 1)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == selectedVersions.count - 1)
                                .help("Move later")

                                Button(role: .destructive) {
                                    selectedVersions.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove from fallback chain")
                            }
                        }
                    }

                    Divider()

                    HStack {
                        TextField(
                            "Exact version, system, ref:…, or path:…",
                            text: $manualVersion
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addManualVersion() }

                        Button("Add Version", systemImage: "plus") {
                            addManualVersion()
                        }
                        .disabled(manualVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Add system") {
                            addVersion("system")
                        }
                        .disabled(selectedVersions.contains("system"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Version catalog") {
                VStack(alignment: .leading, spacing: 10) {
                    if normalizedTool.isEmpty {
                        Text("Choose a tool to load its asdf version catalog.")
                            .foregroundStyle(.secondary)
                    } else if !isInstalledPlugin {
                        Text("This tool does not currently have an installed asdf plugin. You can still enter exact values manually; install the plugin to browse its version catalog.")
                            .foregroundStyle(.secondary)
                    } else if isLoadingCatalog {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading versions…").foregroundStyle(.secondary)
                        }
                    } else if let catalog {
                        TextField("Filter versions", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredRecords) { record in
                                    HStack(spacing: 10) {
                                        Text(record.version)
                                            .font(.system(.body, design: .monospaced))
                                        Spacer()
                                        if record.isInstalled {
                                            Label("Installed", systemImage: "checkmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if record.isLatest {
                                            Label("Latest", systemImage: "star.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Button("Add") {
                                            addVersion(record.version)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(.vertical, 6)
                                    if record.id != filteredRecords.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(minHeight: 120, maxHeight: 210)

                        if filteredRecords.isEmpty {
                            Text(searchText.isEmpty ? "All catalog versions are already in the fallback chain." : "No versions match this filter.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if existingRequirement == nil && existingToolNames.contains(normalizedTool) {
                Label("This tool already exists in the project's .tool-versions. Edit the existing entry instead.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Text(saveExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Save with asdf set", systemImage: "checkmark") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || model.hasActiveOperation)
            }
        }
        .padding(24)
        .frame(width: 760, height: 680)
        .task(id: normalizedTool) {
            await loadCatalog()
        }
    }

    private var saveExplanation: String {
        if language == .simplifiedChinese {
            return "保存会在项目目录执行 asdf set"
        }
        return "Save runs asdf set in the project directory"
    }

    private func addManualVersion() {
        let value = manualVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            errorMessage = ProjectToolVersionsError.invalidVersion(value).localizedDescription
            return
        }
        addVersion(value)
        manualVersion = ""
    }

    private func addVersion(_ value: String) {
        guard !selectedVersions.contains(value) else { return }
        selectedVersions.append(value)
        errorMessage = nil
    }

    private func moveVersion(at index: Int, offset: Int) {
        let target = index + offset
        guard selectedVersions.indices.contains(index), selectedVersions.indices.contains(target) else { return }
        selectedVersions.swapAt(index, target)
    }

    private func loadCatalog() async {
        catalog = nil
        searchText = ""
        errorMessage = nil

        guard !normalizedTool.isEmpty, isInstalledPlugin else { return }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }

        do {
            let loaded = try await model.loadProjectToolVersionCatalog(tool: normalizedTool)
            guard !Task.isCancelled else { return }
            catalog = loaded
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await model.setProjectToolVersions(
                project: project,
                tool: normalizedTool,
                versions: selectedVersions
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
