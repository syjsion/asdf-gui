import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ProjectsPolishedView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationModel.self) private var appNavigation
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var activity = ProjectActivityModel()
    @State private var isAddingProject = false
    @State private var importerError: String?
    @State private var searchText = ""
    @State private var sortOrder: ProjectSortOrder = .name
    @State private var projectScope: ProjectListScope = .all

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var displayedSnapshots: [ProjectSnapshot] {
        ProjectListPlanner.displayedSnapshots(
            model.projectSnapshots,
            searchText: searchText,
            scope: projectScope,
            sortOrder: sortOrder,
            favoritePaths: activity.favoritePaths,
            lastUsedDates: activity.lastUsedDates
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Projects")
                        .font(.largeTitle.bold())
                    Text("Inspect and manage each project's .tool-versions with asdf-backed actions.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRefreshingVersionStatus {
                    ProgressView().controlSize(.small)
                }

                Picker(language.localized("Project list"), selection: $projectScope) {
                    ForEach(ProjectListScope.allCases) { scope in
                        Text(language.localized(scope.titleKey)).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .accessibilityLabel(Text(language.localized("Project list")))

                Menu {
                    Picker(language.localized("Sort projects"), selection: $sortOrder) {
                        ForEach(ProjectSortOrder.allCases) { order in
                            Text(language.localized(order.titleKey)).tag(order)
                        }
                    }
                } label: {
                    Label {
                        Text(language.localized("Sort"))
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                .accessibilityHint(Text(language.localized("Choose how managed projects are ordered.")))

                Button("Add Project", systemImage: "plus") {
                    isAddingProject = true
                }
                .disabled(model.hasActiveOperation)
                .accessibilityHint(Text(language.localized("Choose one or more project folders to manage.")))
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
            } else if displayedSnapshots.isEmpty {
                if projectScope == .favorites && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        language.localized("No favorite projects"),
                        systemImage: "star",
                        description: Text(language.localized("Mark frequently used projects as favorites to keep them at the top and filter to them quickly."))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(displayedSnapshots) { snapshot in
                            ProjectCard(snapshot: snapshot, activity: activity)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(28)
        .searchable(text: $searchText, prompt: language.localized("Search projects, paths, or tools"))
        .toolbar {
            Button("Refresh Projects", systemImage: "arrow.clockwise") {
                Task { await model.reloadProjects() }
            }
            .disabled(model.hasActiveOperation)
            .accessibilityHint(Text(language.localized("Reload project files and installed runtime status.")))
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
        .task {
            activity.prune(to: model.projects)
            applyNavigationSearchIfNeeded()
        }
        .onChange(of: model.projects) { _, projects in
            activity.prune(to: projects)
        }
        .onChange(of: appNavigation.projectSearchRequest) { _, _ in
            applyNavigationSearchIfNeeded()
        }
    }

    private func applyNavigationSearchIfNeeded() {
        guard let query = appNavigation.consumeProjectSearchRequest() else { return }
        projectScope = .all
        searchText = query
    }
}

@MainActor
private struct ProjectCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var isManagingToolVersions = false
    let snapshot: ProjectSnapshot
    let activity: ProjectActivityModel

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
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text(snapshot.project.name)
                                .font(.headline)
                            if activity.isFavorite(snapshot.project) {
                                Label(language.localized("Favorite"), systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.iconOnly)
                                    .accessibilityLabel(Text(language.localized("Favorite project")))
                            }
                        }
                        Text(snapshot.project.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        if let lastUsed = activity.lastUsedDates[snapshot.project.path] {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .accessibilityHidden(true)
                                Text(language.localized("Last used"))
                                Text(lastUsed, style: .relative)
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Spacer(minLength: 16)

                    HStack(spacing: 10) {
                        Button {
                            activity.toggleFavorite(snapshot.project)
                        } label: {
                            Image(systemName: activity.isFavorite(snapshot.project) ? "star.fill" : "star")
                        }
                        .buttonStyle(.borderless)
                        .help(language.localized(activity.isFavorite(snapshot.project) ? "Remove from Favorites" : "Add to Favorites"))
                        .accessibilityLabel(Text(language.localized(activity.isFavorite(snapshot.project) ? "Remove from Favorites" : "Add to Favorites")))

                        Button(language.localized("Reveal in Finder"), systemImage: "finder") {
                            activity.markUsed(snapshot.project)
                            NSWorkspace.shared.activateFileViewerSelecting([snapshot.project.url])
                        }
                        .buttonStyle(.borderless)
                        .accessibilityHint(Text(language.localized("Reveal this managed project folder in Finder.")))

                        Button("Manage .tool-versions", systemImage: "slider.horizontal.3") {
                            activity.markUsed(snapshot.project)
                            isManagingToolVersions = true
                        }
                        .disabled(model.hasActiveOperation)
                        .accessibilityHint(Text(language.localized("Open the structured .tool-versions editor for this project.")))

                        Button(role: .destructive) {
                            activity.remove(snapshot.project)
                            model.removeProject(snapshot.project)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.hasActiveOperation)
                        .help("Remove from asdf GUI. Files are not deleted.")
                    }
                }

                Divider()
                projectContents(installPlan: installPlan)
            }
            .padding(4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(projectAccessibilityLabel))
        .sheet(isPresented: $isManagingToolVersions) {
            ProjectToolVersionsManagerView(project: snapshot.project)
        }
    }

    private var projectAccessibilityLabel: String {
        let favorite = activity.isFavorite(snapshot.project) ? ", \(language.localized("Favorite"))" : ""
        return "\(snapshot.project.name)\(favorite)"
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
                ForEach(Array(snapshot.requirements.enumerated()), id: \.offset) { index, requirement in
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
                            activity.markUsed(snapshot.project)
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
        language == .simplifiedChinese
            ? "待安装 \(count) 个运行时"
            : "\(count) planned runtime\(count == 1 ? "" : "s")"
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
                    .foregroundStyle(requirementStyle)
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 120, idealWidth: 150, maxWidth: 180, alignment: .leading)
            .accessibilityLabel(Text(requirementAccessibilityLabel))

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(requirement.versions.enumerated()), id: \.offset) { index, version in
                    let status = model.status(for: requirement.tool, version: version)
                    HStack(spacing: 8) {
                        Image(systemName: statusSymbol(status))
                            .frame(width: 16)
                            .foregroundStyle(statusStyle(status))
                            .accessibilityHidden(true)
                        Text(version)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Text(language.localized(statusTitle(status)))
                            .font(.caption)
                            .foregroundStyle(statusStyle(status))
                        if index < requirement.versions.count - 1 {
                            Text("fallback")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(versionAccessibilityLabel(version: version, status: status, isFallback: index > 0)))
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

    private var requirementAccessibilityLabel: String {
        let state = model.isRequirementSatisfied(requirement)
            ? language.localized("Satisfied")
            : language.localized("Needs attention")
        return "\(requirement.tool), \(state)"
    }

    private func versionAccessibilityLabel(
        version: String,
        status: RequirementVersionStatus,
        isFallback: Bool
    ) -> String {
        let fallback = isFallback ? ", \(language.localized("fallback"))" : ""
        return "\(requirement.tool) \(version), \(language.localized(statusTitle(status)))\(fallback)"
    }

    private var requirementStyle: AnyShapeStyle {
        model.isRequirementSatisfied(requirement)
            ? AnyShapeStyle(.secondary)
            : AnyShapeStyle(Color.orange)
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

    private func statusStyle(_ status: RequirementVersionStatus) -> AnyShapeStyle {
        statusNeedsAttention(status)
            ? AnyShapeStyle(Color.red)
            : AnyShapeStyle(.secondary)
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

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

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
                LabeledContent("Active path", value: model.executableURL?.path ?? language.localized("Not detected"))
                LabeledContent(
                    "Selection",
                    value: model.configuredExecutableURL == nil
                        ? language.localized("Automatic")
                        : language.localized("Custom")
                )

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
