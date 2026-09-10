import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ApplicationRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AsdfBootstrapModel.self) private var bootstrap
    @Environment(\.openWindow) private var openWindow
    @AppStorage("asdfGUI.hasPresentedGettingStarted") private var hasPresentedGettingStarted = false

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
                MainNavigationView()
            }
        }
        .task {
            if model.executableURL == nil {
                await model.refresh()
            }
            presentGettingStartedIfNeeded()
        }
        .onChange(of: model.executableURL?.path) { _, _ in presentGettingStartedIfNeeded() }
        .onChange(of: model.plugins) { _, _ in presentGettingStartedIfNeeded() }
    }

    private func presentGettingStartedIfNeeded() {
        guard !hasPresentedGettingStarted,
              !model.isLoading,
              model.executableURL != nil,
              model.plugins.isEmpty,
              model.projects.isEmpty else { return }
        hasPresentedGettingStarted = true
        openWindow(id: "getting-started")
    }
}

private enum MainSidebarItem: String, CaseIterable, Identifiable {
    case overview
    case projects
    case versions
    case plugins

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .projects: "Projects"
        case .versions: "Versions"
        case .plugins: "Plugins"
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .projects: "folder"
        case .versions: "square.stack.3d.up"
        case .plugins: "shippingbox"
        }
    }
}

@MainActor
struct MainNavigationView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: MainSidebarItem? = .overview

    var body: some View {
        NavigationSplitView {
            List(MainSidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("asdf GUI")
            .navigationSplitViewColumnWidth(min: 170, ideal: 205, max: 240)
        } detail: {
            switch selection ?? .overview {
            case .overview: OverviewView()
            case .projects: ProjectsPolishedView()
            case .versions: VersionsView()
            case .plugins: PluginsView()
            }
        }
        .task { await model.refresh() }
    }
}

@MainActor
struct ProjectsPolishedView: View {
    @Environment(AppModel.self) private var model
    @State private var isAddingProject = false
    @State private var importerError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projects")
                        .font(.largeTitle.bold())
                    Text("Compare each project's .tool-versions with runtimes installed by asdf.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshingVersionStatus {
                    ProgressView().controlSize(.small)
                }
                Button("Add Project", systemImage: "plus") {
                    isAddingProject = true
                }
                .disabled(model.hasActiveOperation)
            }

            if let importerError {
                Label(importerError, systemImage: "exclamationmark.triangle")
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(model.projectSnapshots) { snapshot in
                            ProjectCard(snapshot: snapshot)
                        }
                    }
                    .padding(.vertical, 2)
                }
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

@MainActor
private struct ProjectCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    let snapshot: ProjectSnapshot

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some View {
        let installPlan = model.installPlan(for: snapshot)

        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.project.name)
                            .font(.headline)
                        Text(snapshot.project.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 16)

                    Button(role: .destructive) {
                        model.removeProject(snapshot.project)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.hasActiveOperation)
                    .help("Remove from asdf GUI. Files are not deleted.")
                }

                Divider()

                projectContents(installPlan: installPlan)
            }
            .padding(4)
        }
        .groupBoxStyle(.automatic)
    }

    @ViewBuilder
    private func projectContents(installPlan: [ProjectInstallItem]) -> some View {
        if let error = snapshot.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.callout)
                .textSelection(.enabled)
        } else if !snapshot.hasToolVersionsFile {
            Label("No .tool-versions in this folder", systemImage: "doc.badge.ellipsis")
                .foregroundStyle(.secondary)
        } else if snapshot.requirements.isEmpty {
            Text(".tool-versions contains no tool entries.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(snapshot.requirements.enumerated()), id: \.element.id) { index, requirement in
                    ProjectRequirementLine(requirement: requirement)
                    if index < snapshot.requirements.count - 1 {
                        Divider().padding(.vertical, 9)
                    }
                }

                if !installPlan.isEmpty {
                    Divider().padding(.vertical, 10)
                    HStack {
                        Text(plannedText(installPlan.count))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Install Missing", systemImage: "arrow.down.circle") {
                            model.installMissing(for: snapshot)
                        }
                        .disabled(model.hasActiveOperation || model.executableURL == nil)
                        .help("Install the first missing version for each unsatisfied tool requirement.")
                    }
                }
            }
        }
    }

    private func plannedText(_ count: Int) -> String {
        if language == .simplifiedChinese {
            return "待安装 \(count) 个运行时"
        }
        return "\(count) planned runtime\(count == 1 ? "" : "s")"
    }
}

@MainActor
private struct ProjectRequirementLine: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    let requirement: ToolRequirement

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Label {
                Text(requirement.tool)
                    .fontWeight(.semibold)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: model.isRequirementSatisfied(requirement) ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(model.isRequirementSatisfied(requirement) ? .secondary : .orange)
            }
            .frame(minWidth: 120, idealWidth: 150, maxWidth: 180, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(requirement.versions.enumerated()), id: \.offset) { index, version in
                    let status = model.status(for: requirement.tool, version: version)
                    HStack(spacing: 8) {
                        Image(systemName: statusSymbol(status))
                            .frame(width: 16)
                            .foregroundStyle(statusNeedsAttention(status) ? .red : .secondary)
                        Text(version)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Text(language.localized(statusTitle(status)))
                            .font(.caption)
                            .foregroundStyle(statusNeedsAttention(status) ? .red : .secondary)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusTitle(_ status: RequirementVersionStatus) -> String {
        switch status {
        case .installed: "Installed"
        case .missing: "Missing"
        case .system: "System"
        case .path: "Local path"
        case .pluginMissing: "Plugin missing"
        case .unknown: "Unknown"
        }
    }

    private func statusSymbol(_ status: RequirementVersionStatus) -> String {
        switch status {
        case .installed: "checkmark.circle.fill"
        case .missing: "arrow.down.circle"
        case .system: "desktopcomputer"
        case .path: "folder"
        case .pluginMissing: "shippingbox.and.arrow.backward"
        case .unknown: "questionmark.circle"
        }
    }

    private func statusNeedsAttention(_ status: RequirementVersionStatus) -> Bool {
        switch status {
        case .missing, .pluginMissing: true
        case .installed, .system, .path, .unknown: false
        }
    }
}

@MainActor
struct AppSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isChoosingExecutable = false
    @State private var importerError: String?
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue

    var body: some View {
        Form {
            Section("Language") {
                Picker("Interface language", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("Language changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("asdf executable") {
                LabeledContent("Active path", value: model.executableURL?.path ?? String(localized: "Not detected"))
                LabeledContent("Selection", value: model.configuredExecutableURL == nil ? String(localized: "Automatic") : String(localized: "Custom"))

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
        .frame(width: 640, height: 380)
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
