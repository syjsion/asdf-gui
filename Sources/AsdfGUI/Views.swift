import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon).tag(item)
            }
            .navigationTitle("asdf GUI")
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .projects: ProjectsView()
            case .versions: VersionsView()
            case .plugins: PluginsView()
            }
        }
        .task { await model.refresh() }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, projects, versions, plugins

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .projects: "folder"
        case .versions: "square.stack.3d.up"
        case .plugins: "shippingbox"
        }
    }
}

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Environment").font(.largeTitle.bold())
                        Text("Local asdf status and installation details").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                }

                GroupBox {
                    LabeledContent("asdf", value: model.asdfVersion)
                    Divider()
                    LabeledContent("Executable", value: model.executableURL?.path ?? "Not found")
                    Divider()
                    LabeledContent("Plugins", value: "\(model.plugins.count)")
                    Divider()
                    LabeledContent("Managed projects", value: "\(model.projects.count)")
                }

                if let error = model.errorMessage {
                    ContentUnavailableView("asdf unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
                }
            }
            .padding(28)
        }
        .overlay { if model.isLoading { ProgressView().controlSize(.large) } }
    }
}

struct ProjectsView: View {
    @Environment(AppModel.self) private var model
    @State private var isAddingProject = false
    @State private var importerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Projects").font(.largeTitle.bold())
                    Text("Compare each project's .tool-versions with runtimes installed by asdf.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshingVersionStatus {
                    ProgressView().controlSize(.small)
                }
                Button("Add Project", systemImage: "plus") { isAddingProject = true }
                    .disabled(model.hasActiveOperation)
            }

            if let importerError {
                Text(importerError)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            if let task = model.activeInstallTask {
                InstallTaskPanel(task: task)
            }

            if model.projectSnapshots.isEmpty {
                ContentUnavailableView(
                    "No projects",
                    systemImage: "folder.badge.plus",
                    description: Text("Add project folders to inspect their .tool-versions files.")
                )
            } else {
                List(model.projectSnapshots) { snapshot in
                    ProjectRow(snapshot: snapshot)
                }
                .listStyle(.inset)
            }
        }
        .padding(28)
        .toolbar {
            Button("Refresh Projects", systemImage: "arrow.clockwise") {
                Task { await model.reloadProjects() }
            }
            .disabled(model.hasActiveOperation)
        }
        .fileImporter(
            isPresented: $isAddingProject,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importerError = nil
                model.addProjects(urls)
            case .failure(let error):
                importerError = error.localizedDescription
            }
        }
    }
}

struct InstallTaskPanel: View {
    @Environment(AppModel.self) private var model
    let task: ProjectInstallTaskState

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(task.status.title, systemImage: task.status.symbolName)
                        .font(.headline)
                    Spacer()
                    if task.isRunning {
                        Button("Cancel", role: .destructive) {
                            model.cancelInstallTask()
                        }
                    } else {
                        Button("Close") {
                            model.dismissInstallTask()
                        }
                    }
                }

                HStack(spacing: 8) {
                    Text(task.project.name).fontWeight(.medium)
                    Text("•").foregroundStyle(.tertiary)
                    Text("\(task.items.count) planned runtime\(task.items.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)

                if let item = task.currentItem {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Installing \(item.tool) \(item.version)…")
                    }
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
                .frame(minHeight: 110, maxHeight: 190)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
        } label: {
            Text("Install Task")
        }
    }
}

struct ProjectRow: View {
    @Environment(AppModel.self) private var model
    let snapshot: ProjectSnapshot

    var body: some View {
        let installPlan = model.installPlan(for: snapshot)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.project.name).font(.headline)
                    Text(snapshot.project.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button(role: .destructive) {
                    model.removeProject(snapshot.project)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(model.hasActiveOperation)
                .help("Remove from asdf GUI. Files are not deleted.")
            }

            if let error = snapshot.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if !snapshot.hasToolVersionsFile {
                Label("No .tool-versions in this folder", systemImage: "doc.badge.ellipsis")
                    .foregroundStyle(.secondary)
            } else if snapshot.requirements.isEmpty {
                Text(".tool-versions contains no tool entries.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(snapshot.requirements) { requirement in
                        RequirementRow(requirement: requirement)
                    }

                    if !installPlan.isEmpty {
                        HStack {
                            Spacer()
                            Button("Install Missing (\(installPlan.count))", systemImage: "arrow.down.circle") {
                                model.installMissing(for: snapshot)
                            }
                            .disabled(model.hasActiveOperation || model.executableURL == nil)
                            .help("Install the first missing version for each unsatisfied tool requirement.")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct RequirementRow: View {
    @Environment(AppModel.self) private var model
    let requirement: ToolRequirement

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: model.isRequirementSatisfied(requirement) ? "checkmark.circle.fill" : "exclamationmark.circle")
                Text(requirement.tool).fontWeight(.medium)
            }
            .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(requirement.versions.enumerated()), id: \.offset) { index, version in
                    let status = model.status(for: requirement.tool, version: version)
                    HStack(spacing: 6) {
                        Image(systemName: status.symbolName).frame(width: 16)
                        Text(version).textSelection(.enabled)
                        Text(status.title)
                            .font(.caption)
                            .foregroundStyle(status.isAttentionNeeded ? .red : .secondary)
                        if index < requirement.versions.count - 1 {
                            Text("fallback")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if let error = model.versionLookupErrors[requirement.tool] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct VersionsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedTool: String?
    @State private var searchText = ""
    @State private var scope: VersionBrowserScope = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Versions").font(.largeTitle.bold())
                    Text("Browse, install, and uninstall versions for each installed plugin.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoadingVersionBrowser {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    guard let selectedTool else { return }
                    Task { await model.loadVersionBrowser(tool: selectedTool) }
                }
                .disabled(selectedTool == nil || model.isLoadingVersionBrowser || model.hasActiveOperation)
            }

            if let task = model.activeVersionOperation {
                VersionOperationPanel(task: task)
            } else if model.activeInstallTask?.isRunning == true {
                Label(
                    "A project install task is running. Version actions are temporarily disabled.",
                    systemImage: "hourglass"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if model.plugins.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    "No plugins",
                    systemImage: "shippingbox",
                    description: Text("Install an asdf plugin before browsing runtime versions.")
                )
            } else {
                HSplitView {
                    List(model.plugins, selection: $selectedTool) { plugin in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plugin.name).fontWeight(.medium)
                            if let count = model.installedVersionsByTool[plugin.name]?.count {
                                Text("\(count) installed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(plugin.name)
                    }
                    .frame(minWidth: 170, idealWidth: 210, maxWidth: 250)
                    .disabled(model.hasActiveOperation)

                    VersionBrowserDetail(searchText: searchText, scope: scope)
                        .frame(minWidth: 440)
                }
            }
        }
        .padding(28)
        .searchable(text: $searchText, prompt: "Filter versions")
        .toolbar {
            ToolbarItem {
                Picker("Scope", selection: $scope) {
                    ForEach(VersionBrowserScope.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
        }
        .onAppear {
            if selectedTool == nil {
                selectedTool = model.plugins.first?.name
            }
        }
        .onChange(of: model.plugins) { _, plugins in
            if let selectedTool, plugins.contains(where: { $0.name == selectedTool }) {
                return
            }
            selectedTool = plugins.first?.name
        }
        .task(id: selectedTool) {
            guard let selectedTool else {
                model.resetVersionBrowser()
                return
            }
            await model.loadVersionBrowser(tool: selectedTool)
        }
    }
}

struct VersionOperationPanel: View {
    @Environment(AppModel.self) private var model
    let task: VersionOperationTaskState

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(task.panelTitle, systemImage: task.status.symbolName)
                        .font(.headline)
                    Spacer()
                    if task.isRunning {
                        Button("Cancel", role: .destructive) {
                            model.cancelVersionOperation()
                        }
                    } else {
                        Button("Close") {
                            model.dismissVersionOperation()
                        }
                    }
                }

                Text("\(task.tool) \(task.version)")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)

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
                .frame(minHeight: 90, maxHeight: 170)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
        } label: {
            Text("Version Task")
        }
    }
}

private enum VersionBrowserScope: String, CaseIterable, Identifiable {
    case all
    case installed

    var id: String { rawValue }
    var title: String { self == .all ? "All" : "Installed" }
}

private struct PendingVersionUninstall {
    let tool: String
    let version: String
}

@MainActor
private struct VersionBrowserDetail: View {
    @Environment(AppModel.self) private var model
    @State private var pendingUninstall: PendingVersionUninstall?
    @State private var isShowingUninstallConfirmation = false
    let searchText: String
    let scope: VersionBrowserScope

    var records: [ToolVersionRecord] {
        var records = VersionCatalog.records(
            available: model.versionBrowserAvailableVersions,
            installed: model.versionBrowserInstalledVersions,
            latest: model.versionBrowserLatestVersion
        )

        if scope == .installed {
            records = records.filter(\.isInstalled)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            records = records.filter { $0.version.localizedCaseInsensitiveContains(query) }
        }
        return records
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let tool = model.versionBrowserTool {
                HStack(alignment: .firstTextBaseline) {
                    Text(tool).font(.title2.bold())
                    Spacer()
                    Text("\(model.versionBrowserInstalledVersions.count) installed")
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    LabeledContent("Latest", value: model.versionBrowserLatestVersion ?? "—")
                    Divider()
                    LabeledContent("Available", value: "\(model.versionBrowserAvailableVersions.count)")
                    Divider()
                    LabeledContent("Installed", value: "\(model.versionBrowserInstalledVersions.count)")
                }

                if !model.versionBrowserErrors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.versionBrowserErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                }

                if records.isEmpty && !model.isLoadingVersionBrowser {
                    ContentUnavailableView(
                        scope == .installed ? "No installed versions" : "No matching versions",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text(searchText.isEmpty ? "No versions were returned for this plugin." : "Try a different search term.")
                    )
                } else {
                    Table(records) {
                        TableColumn("Version") { record in
                            Text(record.version)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        TableColumn("Status") { record in
                            HStack(spacing: 8) {
                                if record.isInstalled {
                                    Label("Installed", systemImage: "checkmark.circle.fill")
                                }
                                if record.isLatest {
                                    Label("Latest", systemImage: "star.fill")
                                }
                                if !record.isInstalled && !record.isLatest {
                                    Text("Available").foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                        }
                        TableColumn("Action") { record in
                            if record.isInstalled {
                                Button(role: .destructive) {
                                    pendingUninstall = PendingVersionUninstall(tool: tool, version: record.version)
                                    isShowingUninstallConfirmation = true
                                } label: {
                                    Label("Uninstall", systemImage: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.hasActiveOperation)
                            } else {
                                Button {
                                    model.installVersionFromBrowser(tool: tool, version: record.version)
                                } label: {
                                    Label("Install", systemImage: "arrow.down.circle")
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.hasActiveOperation || model.executableURL == nil)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a plugin",
                    systemImage: "shippingbox",
                    description: Text("Choose an installed asdf plugin to browse its versions.")
                )
            }
        }
        .padding(.leading, 12)
        .alert(
            "Uninstall version?",
            isPresented: $isShowingUninstallConfirmation,
            presenting: pendingUninstall
        ) { request in
            Button("Uninstall", role: .destructive) {
                model.uninstallVersionFromBrowser(tool: request.tool, version: request.version)
                pendingUninstall = nil
            }
            Button("Cancel", role: .cancel) {
                pendingUninstall = nil
            }
        } message: { request in
            Text(uninstallMessage(for: request))
        }
    }

    private func uninstallMessage(for request: PendingVersionUninstall) -> String {
        let projects = model.projectsUsing(tool: request.tool, version: request.version)
        guard !projects.isEmpty else {
            return "This removes \(request.tool) \(request.version) from asdf. Reinstalling will be required to use it again."
        }

        let projectList = projects
            .map { "• \($0.name) — \($0.path)" }
            .joined(separator: "\n")
        return "This version is referenced by \(projects.count) managed project\(projects.count == 1 ? "" : "s"):\n\n\(projectList)\n\nUninstalling may leave those projects with a missing runtime unless another configured fallback remains usable."
    }
}

private extension ProjectInstallTaskStatus {
    var title: String {
        switch self {
        case .running: "Installing runtimes"
        case .succeeded: "Installation complete"
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

private extension VersionOperationTaskState {
    var panelTitle: String {
        switch status {
        case .running:
            return kind == .install ? "Installing version" : "Uninstalling version"
        case .succeeded:
            return kind == .install ? "Installation complete" : "Uninstall complete"
        case .failed:
            return kind == .install ? "Installation failed" : "Uninstall failed"
        case .cancelled:
            return "Version operation cancelled"
        }
    }
}

private extension VersionOperationStatus {
    var symbolName: String {
        switch self {
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }
}

private extension RequirementVersionStatus {
    var title: String {
        switch self {
        case .installed: "Installed"
        case .missing: "Missing"
        case .system: "System"
        case .path: "Local path"
        case .pluginMissing: "Plugin missing"
        case .unknown: "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .installed: "checkmark.circle.fill"
        case .missing: "arrow.down.circle"
        case .system: "desktopcomputer"
        case .path: "folder"
        case .pluginMissing: "shippingbox.and.arrow.backward"
        case .unknown: "questionmark.circle"
        }
    }

    var isAttentionNeeded: Bool {
        switch self {
        case .missing, .pluginMissing:
            return true
        case .installed, .system, .path, .unknown:
            return false
        }
    }
}

struct PluginsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Plugins").font(.largeTitle.bold())
            if model.plugins.isEmpty && !model.isLoading {
                ContentUnavailableView("No plugins", systemImage: "shippingbox", description: Text("Install an asdf plugin or refresh the environment."))
            } else {
                Table(model.plugins) {
                    TableColumn("Plugin") { plugin in Text(plugin.name).fontWeight(.medium) }
                    TableColumn("Repository") { plugin in Text(plugin.url ?? "—").foregroundStyle(.secondary) }
                }
            }
        }
        .padding(28)
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } } }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isChoosingExecutable = false
    @State private var importerError: String?

    var body: some View {
        Form {
            Section("asdf executable") {
                LabeledContent("Active path", value: model.executableURL?.path ?? "Not detected")
                LabeledContent("Selection", value: model.configuredExecutableURL == nil ? "Automatic" : "Custom")

                HStack {
                    Button("Choose asdf…") { isChoosingExecutable = true }
                    Button("Use Automatic Detection") {
                        Task { await model.resetExecutablePreference() }
                    }
                    .disabled(model.configuredExecutableURL == nil)
                }

                if let importerError {
                    Text(importerError).foregroundStyle(.red).font(.caption)
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                Text("The selected file must be executable. Automatic detection checks common Homebrew, ~/.local/bin, and ~/go/bin locations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 280)
        .fileImporter(
            isPresented: $isChoosingExecutable,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importerError = nil
                Task { await model.setExecutable(url) }
            case .failure(let error):
                importerError = error.localizedDescription
            }
        }
    }
}
