import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ProjectSortOrder: String, CaseIterable, Identifiable {
    case name
    case path
    case toolCount

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .name: "Name"
        case .path: "Path"
        case .toolCount: "Tool count"
        }
    }
}

@MainActor
struct ProjectsPolishedView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigationModel.self) private var appNavigation
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var isAddingProject = false
    @State private var importerError: String?
    @State private var searchText = ""
    @State private var sortOrder: ProjectSortOrder = .name

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var displayedSnapshots: [ProjectSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = model.projectSnapshots.filter { snapshot in
            query.isEmpty
                || snapshot.project.name.localizedCaseInsensitiveContains(query)
                || snapshot.project.path.localizedCaseInsensitiveContains(query)
                || snapshot.requirements.contains { $0.tool.localizedCaseInsensitiveContains(query) }
        }

        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .name:
                return lhs.project.name.localizedCaseInsensitiveCompare(rhs.project.name) == .orderedAscending
            case .path:
                return lhs.project.path.localizedCaseInsensitiveCompare(rhs.project.path) == .orderedAscending
            case .toolCount:
                if lhs.requirements.count == rhs.requirements.count {
                    return lhs.project.name.localizedCaseInsensitiveCompare(rhs.project.name) == .orderedAscending
                }
                return lhs.requirements.count > rhs.requirements.count
            }
        }
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
                .accessibilityHint(language.localized("Choose how managed projects are ordered."))

                Button("Add Project", systemImage: "plus") {
                    isAddingProject = true
                }
                .disabled(model.hasActiveOperation)
                .accessibilityHint(language.localized("Choose one or more project folders to manage."))
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
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(displayedSnapshots) { snapshot in
                            ProjectCard(snapshot: snapshot)
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
            .accessibilityHint(language.localized("Reload project files and installed runtime status."))
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
        .task { applyNavigationSearchIfNeeded() }
        .onChange(of: appNavigation.projectSearchRequest) { _, _ in
            applyNavigationSearchIfNeeded()
        }
    }

    private func applyNavigationSearchIfNeeded() {
        guard let query = appNavigation.consumeProjectSearchRequest() else { return }
        searchText = query
    }
}

@MainActor
private struct ProjectCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var isManagingToolVersions = false
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
                        .accessibilityHidden(true)

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

                    HStack(spacing: 10) {
                        Button(language.localized("Reveal in Finder"), systemImage: "finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([snapshot.project.url])
                        }
                        .buttonStyle(.borderless)
                        .accessibilityHint(language.localized("Reveal this managed project folder in Finder."))

                        Button("Manage .tool-versions", systemImage: "slider.horizontal.3") {
                            isManagingToolVersions = true
                        }
                        .disabled(model.hasActiveOperation)
                        .accessibilityHint(language.localized("Open the structured .tool-versions editor for this project."))

                        Button(role: .destructive) {
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
        .accessibilityLabel(snapshot.project.name)
        .sheet(isPresented: $isManagingToolVersions) {
            ProjectToolVersionsManagerView(project: snapshot.project)
        }
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
            .accessibilityLabel(requirementAccessibilityLabel)

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
                    .accessibilityLabel(versionAccessibilityLabel(version: version, status: status, isFallback: index > 0))
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
