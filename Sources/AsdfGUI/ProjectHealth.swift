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

struct ProjectHealthIssue: Identifiable, Hashable, Sendable {
    let id: String
    let severity: ProjectHealthSeverity
    let title: String
    let detail: String
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
            let states = requirement.versions.map { status(requirement.tool, $0) }
            if states.contains(where: \.isSatisfied) { continue }

            if states.contains(.pluginMissing) {
                issues.append(ProjectHealthIssue(
                    id: "plugin-missing-\(requirement.tool)",
                    severity: .error,
                    title: "Plugin missing: \(requirement.tool)",
                    detail: "Install the \(requirement.tool) plugin before this project can use its configured runtime."
                ))
            } else if states.contains(.unknown) {
                issues.append(ProjectHealthIssue(
                    id: "lookup-failed-\(requirement.tool)",
                    severity: .warning,
                    title: "Runtime status unknown: \(requirement.tool)",
                    detail: "asdf could not determine installed versions for this tool. Refresh or inspect Diagnostics."
                ))
            } else {
                issues.append(ProjectHealthIssue(
                    id: "runtime-missing-\(requirement.tool)",
                    severity: .error,
                    title: "Runtime missing: \(requirement.tool)",
                    detail: "None of the configured fallbacks are currently usable: \(requirement.versions.joined(separator: " → "))"
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
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.defaultLanguage.rawValue
    @State private var model = ProjectHealthModel()
    @State private var issuesOnly = false

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
                if model.isLoading { ProgressView().controlSize(.small) }
                Toggle(language.localized("Issues only"), isOn: $issuesOnly)
                    .toggleStyle(.checkbox)
                Button(language.localized("Refresh"), systemImage: "arrow.clockwise") {
                    Task { await appModel.reloadProjects(); await model.load(appModel: appModel) }
                }
                .disabled(model.isLoading || appModel.hasActiveOperation)
                Button(language.localized("Close")) { dismiss() }
            }

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
        .frame(minWidth: 820, minHeight: 620)
        .task { await model.load(appModel: appModel) }
    }

    @ViewBuilder
    private func reportCard(_ report: ProjectHealthReport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(report.project.name, systemImage: report.isHealthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.headline)
                    Spacer()
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localizedIssueTitle(issue.title)).fontWeight(.medium)
                                Text(localizedIssueDetail(issue.detail))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
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
