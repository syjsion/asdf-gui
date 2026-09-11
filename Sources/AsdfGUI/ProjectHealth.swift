import Foundation
import Observation
import SwiftUI

enum ProjectHealthSeverity: Int, Comparable, Hashable, Sendable {
    case info = 0
    case warning = 1
    case error = 2

    static func < (lhs: ProjectHealthSeverity, rhs: ProjectHealthSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ProjectHealthFix: Hashable, Sendable {
    case installPlugin(tool: String)
    case installRuntime(tool: String, version: String)
}

struct ProjectHealthIssue: Identifiable, Hashable, Sendable {
    let id: String
    let severity: ProjectHealthSeverity
    let title: String
    let detail: String
    let fix: ProjectHealthFix?

    init(
        id: String,
        severity: ProjectHealthSeverity,
        title: String,
        detail: String,
        fix: ProjectHealthFix? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.fix = fix
    }
}

struct ProjectHealthReport: Identifiable, Hashable, Sendable {
    let project: ManagedProject
    var issues: [ProjectHealthIssue]
    var sourcePaths: [String]

    var id: String { project.id }
    var highestSeverity: ProjectHealthSeverity? { issues.map(\.severity).max() }
    var isHealthy: Bool { !issues.contains { $0.severity == .error || $0.severity == .warning } }
}

enum ProjectHealthAnalyzer {
    static func issues(
        snapshot: ProjectSnapshot,
        status: (String, String) -> RequirementVersionStatus
    ) -> [ProjectHealthIssue] {
        if let error = snapshot.errorMessage {
            return [ProjectHealthIssue(
                id: "snapshot-error",
                severity: .error,
                title: "Project cannot be read",
                detail: error
            )]
        }

        var issues: [ProjectHealthIssue] = []
        if !snapshot.hasToolVersionsFile {
            issues.append(ProjectHealthIssue(
                id: "no-tool-versions",
                severity: .info,
                title: "No project-local .tool-versions",
                detail: "The project may inherit versions from a parent directory or Home."
            ))
        } else if snapshot.requirements.isEmpty {
            issues.append(ProjectHealthIssue(
                id: "empty-tool-versions",
                severity: .warning,
                title: ".tool-versions has no tool entries",
                detail: "Add at least one tool or remove the empty configuration file if it is not needed."
            ))
        }

        for requirement in snapshot.requirements {
            let states = requirement.versions.map { version in
                (version, status(requirement.tool, version))
            }
            if states.contains(where: { $0.1.isSatisfied }) { continue }

            if states.contains(where: { $0.1 == .pluginMissing }) {
                issues.append(ProjectHealthIssue(
                    id: "plugin-missing-\(requirement.tool)",
                    severity: .error,
                    title: "Plugin missing: \(requirement.tool)",
                    detail: "Install the \(requirement.tool) plugin before this project can use its configured runtime.",
                    fix: .installPlugin(tool: requirement.tool)
                ))
            } else if states.contains(where: { $0.1 == .unknown }) {
                issues.append(ProjectHealthIssue(
                    id: "lookup-failed-\(requirement.tool)",
                    severity: .warning,
                    title: "Runtime status unknown: \(requirement.tool)",
                    detail: "asdf could not determine installed versions for this tool. Refresh or inspect Diagnostics."
                ))
            } else {
                let installable = states.first(where: { $0.1 == .missing })?.0
                issues.append(ProjectHealthIssue(
                    id: "runtime-missing-\(requirement.tool)",
                    severity: .error,
                    title: "Runtime missing: \(requirement.tool)",
                    detail: "None of the configured fallbacks are currently usable: \(requirement.versions.joined(separator: " → "))",
                    fix: installable.map { .installRuntime(tool: requirement.tool, version: $0) }
                ))
            }
        }
        return issues
    }
}

@MainActor
@Observable
final class ProjectHealthModel {
    var reports: [ProjectHealthReport] = []
    var isLoading = false

    private let service = AsdfService()

    func load(appModel: AppModel) async {
        isLoading = true
        defer { isLoading = false }

        guard let executable = appModel.executableURL else {
            reports = appModel.projectSnapshots.map { snapshot in
                ProjectHealthReport(
                    project: snapshot.project,
                    issues: [ProjectHealthIssue(
                        id: "asdf-unavailable",
                        severity: .error,
                        title: "asdf unavailable",
                        detail: "Configure or install asdf before checking project health."
                    )],
                    sourcePaths: []
                )
            }
            return
        }

        var loaded: [ProjectHealthReport] = []
        for snapshot in appModel.projectSnapshots {
            var issues = ProjectHealthAnalyzer.issues(snapshot: snapshot) { tool, version in
                appModel.status(for: tool, version: version)
            }
            var sources: [String] = []

            do {
                let current = try await service.current(
                    executable: executable,
                    currentDirectory: snapshot.project.url
                )
                sources = Array(Set(current.compactMap(\.source))).sorted()
                if current.contains(where: { !$0.isInstalled }) {
                    issues.append(ProjectHealthIssue(
                        id: "effective-version-missing",
                        severity: .error,
                        title: "Effective version is not installed",
                        detail: "asdf current reports at least one resolved runtime that is not installed."
                    ))
                }
            } catch {
                issues.append(ProjectHealthIssue(
                    id: "resolution-check-failed",
                    severity: .warning,
                    title: "Effective version check failed",
                    detail: error.localizedDescription
                ))
            }

            loaded.append(ProjectHealthReport(
                project: snapshot.project,
                issues: issues,
                sourcePaths: sources
            ))
        }

        reports = loaded.sorted { lhs, rhs in
            let left = lhs.highestSeverity?.rawValue ?? -1
            let right = rhs.highestSeverity?.rawValue ?? -1
            if left == right {
                return lhs.project.name.localizedCaseInsensitiveCompare(rhs.project.name) == .orderedAscending
            }
            return left > right
        }
    }
}

@MainActor
struct ProjectHealthView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppNavigationModel.self) private var appNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var model = ProjectHealthModel()
    @State private var pluginOperations = PluginManagementModel()
    @State private var pluginDiscovery = PluginDiscoveryModel()
    @State private var issuesOnly = false
    @State private var pendingFix: ProjectHealthFix?
    @State private var pendingProject: ManagedProject?
    @State private var resolvedPluginEntry: AsdfPluginCatalogEntry?
    @State private var isShowingFixConfirmation = false
    @State private var isPreparingFix = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.defaultLanguage
    }

    private var visibleReports: [ProjectHealthReport] {
        issuesOnly ? model.reports.filter { !$0.isHealthy } : model.reports
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.localized("Project Health"))
                        .font(.largeTitle.bold())
                    Text(language.localized("Combine project requirements with asdf resolution to surface missing plugins, runtimes, and inherited configuration sources."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading || isPreparingFix { ProgressView().controlSize(.small) }
                Toggle(language.localized("Issues only"), isOn: $issuesOnly)
                    .toggleStyle(.checkbox)
                Button(language.localized("Refresh"), systemImage: "arrow.clockwise") {
                    Task { await refreshHealth() }
                }
                .disabled(model.isLoading || isPreparingFix || appModel.hasActiveOperation || pluginOperations.isBusy)
                Button(language.localized("Close")) { dismiss() }
            }

            operationPanels

            if visibleReports.isEmpty && !model.isLoading {
                ContentUnavailableView(
                    language.localized("No project health issues"),
                    systemImage: "checkmark.shield",
                    description: Text(language.localized("All managed projects currently satisfy their known asdf requirements."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleReports) { report in
                            reportCard(report)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 660)
        .task { await model.load(appModel: appModel) }
        .onChange(of: appModel.plugins) { _, _ in
            Task { await model.load(appModel: appModel) }
        }
        .onChange(of: appModel.installedVersionsByTool) { _, _ in
            Task { await model.load(appModel: appModel) }
        }
        .onDisappear {
            pluginOperations.cancelOperation()
        }
        .alert(
            language.localized("Apply health fix?"),
            isPresented: $isShowingFixConfirmation,
            presenting: pendingFix
        ) { fix in
            Button(language.localized("Apply Fix")) {
                apply(fix)
            }
            Button(language.localized("Cancel"), role: .cancel) {
                resetPendingFix()
            }
        } message: { fix in
            Text(fixConfirmationMessage(fix))
        }
    }

    @ViewBuilder
    private var operationPanels: some View {
        if let operation = pluginOperations.activeOperation {
            GroupBox(language.localized("Health Fix Task")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(pluginOperationTitle(operation)).font(.headline)
                        Spacer()
                        if operation.isRunning {
                            Button(language.localized("Cancel"), role: .destructive) {
                                pluginOperations.cancelOperation()
                            }
                        } else {
                            Button(language.localized("Close")) {
                                pluginOperations.dismissOperation()
                            }
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
                    }
                    .frame(minHeight: 70, maxHeight: 130)
                }
            }
        }

        if let task = appModel.activeVersionOperation {
            VersionOperationPanel(task: task)
        }
    }

    @ViewBuilder
    private func reportCard(_ report: ProjectHealthReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(report.project.name, systemImage: report.isHealthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.headline)
                    Spacer()
                    Button(language.localized("Show in Projects"), systemImage: "arrow.right.circle") {
                        appNavigation.showProject(report.project)
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(language.localized("Open Projects and filter to this project."))
                    Text(report.project.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if report.issues.isEmpty {
                    Text(language.localized("Healthy"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(report.issues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: symbol(issue.severity))
                                .foregroundStyle(style(issue.severity))
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(severityTitle(issue.severity))
                                        .font(.caption2.bold())
                                        .foregroundStyle(style(issue.severity))
                                    Text(localizedIssueTitle(issue.title))
                                        .fontWeight(.medium)
                                }
                                Text(localizedIssueDetail(issue.detail))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 12)
                            if let fix = issue.fix {
                                HStack(spacing: 8) {
                                    Button(contextButtonTitle(fix)) {
                                        openContext(for: fix)
                                    }
                                    .buttonStyle(.borderless)

                                    Button(fixButtonTitle(fix)) {
                                        prepareFix(fix, project: report.project)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(
                                        model.isLoading
                                            || isPreparingFix
                                            || appModel.hasActiveOperation
                                            || pluginOperations.isBusy
                                    )
                                }
                            }
                        }
                        .accessibilityElement(children: .contain)
                    }
                }

                if !report.sourcePaths.isEmpty {
                    Divider()
                    Text(language.localized("Effective configuration sources"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(report.sourcePaths, id: \.self) { source in
                        Text(source)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(2)
        }
    }

    private func prepareFix(_ fix: ProjectHealthFix, project: ManagedProject) {
        pendingFix = fix
        pendingProject = project
        resolvedPluginEntry = nil

        switch fix {
        case .installPlugin(let tool):
            Task {
                isPreparingFix = true
                if pluginDiscovery.catalog.isEmpty {
                    await pluginDiscovery.load(appModel: appModel)
                }
                resolvedPluginEntry = PluginCatalogResolver.exactEntry(for: tool, in: pluginDiscovery.catalog)
                isPreparingFix = false
                isShowingFixConfirmation = true
            }
        case .installRuntime:
            isShowingFixConfirmation = true
        }
    }

    private func apply(_ fix: ProjectHealthFix) {
        defer { resetPendingFix() }
        switch fix {
        case .installPlugin(let tool):
            if let entry = resolvedPluginEntry {
                pluginOperations.addPlugin(name: entry.name, gitURL: entry.url, appModel: appModel)
            } else {
                pluginOperations.addPlugin(name: tool, gitURL: nil, appModel: appModel)
            }
        case .installRuntime(let tool, let version):
            appModel.installVersionFromBrowser(tool: tool, version: version)
        }
    }

    private func resetPendingFix() {
        pendingFix = nil
        pendingProject = nil
        resolvedPluginEntry = nil
        isPreparingFix = false
    }

    private func openContext(for fix: ProjectHealthFix) {
        switch fix {
        case .installPlugin:
            openWindow(id: "plugin-manager")
            dismiss()
        case .installRuntime(let tool, _):
            appNavigation.showVersions(tool: tool)
            dismiss()
        }
    }

    private func refreshHealth() async {
        await appModel.reloadProjects()
        await model.load(appModel: appModel)
    }

    private func fixButtonTitle(_ fix: ProjectHealthFix) -> String {
        switch fix {
        case .installPlugin:
            return language.localized("Install Plugin")
        case .installRuntime:
            return language.localized("Install Runtime")
        }
    }

    private func contextButtonTitle(_ fix: ProjectHealthFix) -> String {
        switch fix {
        case .installPlugin:
            return language.localized("Plugin Manager")
        case .installRuntime:
            return language.localized("View Versions")
        }
    }

    private func fixConfirmationMessage(_ fix: ProjectHealthFix) -> String {
        let projectSuffix: String
        if let pendingProject {
            projectSuffix = language == .simplifiedChinese
                ? "\n\n项目：\(pendingProject.name)"
                : "\n\nProject: \(pendingProject.name)"
        } else {
            projectSuffix = ""
        }

        switch fix {
        case .installPlugin(let tool):
            if let entry = resolvedPluginEntry, let url = entry.url {
                if language == .simplifiedChinese {
                    return "已从 asdf 插件目录精确匹配到 \(entry.name)。将使用明确的 Git URL 安装：\n\(url)\n\n不会修改任何项目的 .tool-versions。\(projectSuffix)"
                }
                return "An exact match was found in the asdf plugin catalog. The plugin will be installed from this explicit Git URL:\n\(url)\n\nNo project .tool-versions file will be changed.\(projectSuffix)"
            }
            if language == .simplifiedChinese {
                return "插件目录没有提供可用的精确 Git URL，将回退执行 asdf plugin add \(tool)，使用 asdf short-name 仓库。不会修改任何项目的 .tool-versions。\(projectSuffix)"
            }
            return "No usable exact Git URL was found in the plugin catalog. This falls back to asdf plugin add \(tool) using asdf's short-name repository. No project .tool-versions file will be changed.\(projectSuffix)"
        case .installRuntime(let tool, let version):
            if language == .simplifiedChinese {
                return "将执行 asdf install \(tool) \(version)。只安装该精确版本，不会修改项目、父级或 Home 的 .tool-versions。\(projectSuffix)"
            }
            return "This runs asdf install \(tool) \(version). It installs only that exact runtime and does not rewrite Project, Parent, or Home .tool-versions.\(projectSuffix)"
        }
    }

    private func pluginOperationTitle(_ operation: PluginOperationTaskState) -> String {
        switch operation.status {
        case .running: return language.localized("Installing plugin…")
        case .succeeded: return language.localized("Plugin installed")
        case .failed: return language.localized("Plugin installation failed")
        case .cancelled: return language.localized("Plugin installation cancelled")
        }
    }

    private func severityTitle(_ severity: ProjectHealthSeverity) -> String {
        switch severity {
        case .info: language.localized("Info")
        case .warning: language.localized("Warning")
        case .error: language.localized("Error")
        }
    }

    private func symbol(_ severity: ProjectHealthSeverity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon.fill"
        }
    }

    private func style(_ severity: ProjectHealthSeverity) -> AnyShapeStyle {
        switch severity {
        case .info: AnyShapeStyle(.secondary)
        case .warning: AnyShapeStyle(Color.orange)
        case .error: AnyShapeStyle(Color.red)
        }
    }

    private func localizedIssueTitle(_ value: String) -> String {
        guard language == .simplifiedChinese else { return value }
        if value.hasPrefix("Plugin missing:") { return value.replacingOccurrences(of: "Plugin missing:", with: "插件缺失：") }
        if value.hasPrefix("Runtime missing:") { return value.replacingOccurrences(of: "Runtime missing:", with: "运行时缺失：") }
        if value.hasPrefix("Runtime status unknown:") { return value.replacingOccurrences(of: "Runtime status unknown:", with: "运行时状态未知：") }
        return language.localized(value)
    }

    private func localizedIssueDetail(_ value: String) -> String {
        guard language == .simplifiedChinese else { return value }
        return language.localized(value)
    }
}
