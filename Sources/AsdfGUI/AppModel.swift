import Foundation
import Observation

struct AsdfPlugin: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let url: String?
}

enum ProjectInstallTaskStatus: Hashable {
    case running
    case succeeded
    case failed
    case cancelled
}

struct ProjectInstallTaskState: Identifiable {
    let id: UUID
    let project: ManagedProject
    let items: [ProjectInstallItem]
    var status: ProjectInstallTaskStatus
    var currentItem: ProjectInstallItem?
    var log: String
    var errorMessage: String?

    var isRunning: Bool { status == .running }
}

@MainActor
@Observable
final class AppModel {
    var configuredExecutableURL: URL?
    var executableURL: URL?
    var asdfVersion = "Not detected"
    var plugins: [AsdfPlugin] = []
    var projects: [ManagedProject] = []
    var projectSnapshots: [ProjectSnapshot] = []
    var installedVersionsByTool: [String: [String]] = [:]
    var versionLookupErrors: [String: String] = [:]
    var activeInstallTask: ProjectInstallTaskState?
    var isLoading = false
    var isRefreshingVersionStatus = false
    var errorMessage: String?

    private let service = AsdfService()
    private let projectService = ProjectService()
    private let preferences = PreferencesStore()
    private let installLogLimit = 200_000
    private var installTask: Task<Void, Never>?

    init() {
        configuredExecutableURL = preferences.executableURL()
        projects = preferences.projects()
        refreshProjects()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let executable = try service.locateExecutable(preferred: configuredExecutableURL)
            executableURL = executable
            async let version = service.version(executable: executable)
            async let loadedPlugins = service.plugins(executable: executable)
            asdfVersion = try await version
            plugins = try await loadedPlugins
            await refreshInstalledVersions()
        } catch {
            executableURL = nil
            asdfVersion = "Not detected"
            plugins = []
            installedVersionsByTool = [:]
            versionLookupErrors = [:]
            errorMessage = error.localizedDescription
        }
    }

    func setExecutable(_ url: URL) async {
        do {
            let executable = try service.locateExecutable(preferred: url)
            configuredExecutableURL = executable
            preferences.setExecutableURL(executable)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetExecutablePreference() async {
        configuredExecutableURL = nil
        preferences.setExecutableURL(nil)
        await refresh()
    }

    func addProjects(_ urls: [URL]) {
        var updated = projects
        var existingPaths = Set(updated.map(\.path))

        for url in urls {
            let standardized = url.standardizedFileURL
            if existingPaths.insert(standardized.path).inserted {
                updated.append(ManagedProject(path: standardized.path))
            }
        }

        projects = updated.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        preferences.setProjects(projects)
        refreshProjects()
        Task { await refreshInstalledVersions() }
    }

    func removeProject(_ project: ManagedProject) {
        projects.removeAll { $0.id == project.id }
        preferences.setProjects(projects)
        refreshProjects()
        Task { await refreshInstalledVersions() }
    }

    func refreshProjects() {
        projectSnapshots = projects.map { projectService.snapshot(for: $0) }
    }

    func reloadProjects() async {
        refreshProjects()
        await refreshInstalledVersions()
    }

    func refreshInstalledVersions() async {
        guard let executable = executableURL else {
            installedVersionsByTool = [:]
            versionLookupErrors = [:]
            return
        }

        let tools = Set(projectSnapshots.flatMap(\.requirements).map(\.tool))
        let installedPlugins = Set(plugins.map(\.name))
        var versionsByTool: [String: [String]] = [:]
        var lookupErrors: [String: String] = [:]

        isRefreshingVersionStatus = true
        defer { isRefreshingVersionStatus = false }

        for tool in tools.sorted() where installedPlugins.contains(tool) {
            do {
                versionsByTool[tool] = try await service.installedVersions(executable: executable, tool: tool)
            } catch {
                lookupErrors[tool] = error.localizedDescription
            }
        }

        installedVersionsByTool = versionsByTool
        versionLookupErrors = lookupErrors
    }

    func status(for tool: String, version: String) -> RequirementVersionStatus {
        let installed: Set<String>? = installedVersionsByTool[tool].map { Set($0) }
        return RequirementStatusResolver.resolve(
            version: version,
            installedVersions: installed,
            pluginInstalled: plugins.contains { $0.name == tool },
            lookupFailed: versionLookupErrors[tool] != nil
        )
    }

    func isRequirementSatisfied(_ requirement: ToolRequirement) -> Bool {
        requirement.versions.contains { version in
            status(for: requirement.tool, version: version).isSatisfied
        }
    }

    func installPlan(for snapshot: ProjectSnapshot) -> [ProjectInstallItem] {
        ProjectInstallPlanner.plan(requirements: snapshot.requirements) { tool, version in
            status(for: tool, version: version)
        }
    }

    func installMissing(for snapshot: ProjectSnapshot) {
        guard activeInstallTask?.isRunning != true, executableURL != nil else { return }

        let items = installPlan(for: snapshot)
        guard !items.isEmpty else { return }

        let taskID = UUID()
        activeInstallTask = ProjectInstallTaskState(
            id: taskID,
            project: snapshot.project,
            items: items,
            status: .running,
            currentItem: nil,
            log: "Installing missing runtimes for \(snapshot.project.name)\n",
            errorMessage: nil
        )

        installTask = Task { [weak self] in
            await self?.runInstallTask(id: taskID, project: snapshot.project, items: items)
        }
    }

    func cancelInstallTask() {
        guard let state = activeInstallTask, state.isRunning else { return }
        appendInstallLog("\nCancelling…\n", taskID: state.id)
        installTask?.cancel()
    }

    func dismissInstallTask() {
        guard activeInstallTask?.isRunning != true else { return }
        activeInstallTask = nil
    }

    private func runInstallTask(id: UUID, project: ManagedProject, items: [ProjectInstallItem]) async {
        guard let executable = executableURL else {
            finishInstallTask(id: id, status: .failed, error: "asdf executable is not available.")
            return
        }

        for item in items {
            if Task.isCancelled {
                finishInstallTask(id: id, status: .cancelled, error: nil)
                return
            }

            updateInstallTask(id: id) { state in
                state.currentItem = item
            }
            appendInstallLog("\n$ asdf install \(item.tool) \(item.version)\n", taskID: id)

            do {
                _ = try await service.installVersion(
                    executable: executable,
                    tool: item.tool,
                    version: item.version,
                    currentDirectory: project.url
                ) { [weak self] event in
                    Task { [weak self] in
                        await self?.appendInstallOutput(event, taskID: id)
                    }
                }
                appendInstallLog("\n✓ Installed \(item.tool) \(item.version)\n", taskID: id)
            } catch is CancellationError {
                finishInstallTask(id: id, status: .cancelled, error: nil)
                return
            } catch {
                appendInstallLog("\n✗ \(error.localizedDescription)\n", taskID: id)
                finishInstallTask(id: id, status: .failed, error: error.localizedDescription)
                return
            }
        }

        finishInstallTask(id: id, status: .succeeded, error: nil)
        await refreshInstalledVersions()
    }

    private func appendInstallOutput(_ event: AsdfOutputEvent, taskID: UUID) {
        appendInstallLog(event.text, taskID: taskID)
    }

    private func appendInstallLog(_ text: String, taskID: UUID) {
        updateInstallTask(id: taskID) { state in
            state.log += text
            if state.log.count > installLogLimit {
                let retained = String(state.log.suffix(installLogLimit - 64))
                state.log = "… older output truncated …\n" + retained
            }
        }
    }

    private func finishInstallTask(id: UUID, status: ProjectInstallTaskStatus, error: String?) {
        updateInstallTask(id: id) { state in
            state.status = status
            state.currentItem = nil
            state.errorMessage = error
            switch status {
            case .succeeded:
                state.log += "\nAll planned runtimes installed.\n"
            case .cancelled:
                state.log += "\nInstallation cancelled.\n"
            case .failed, .running:
                break
            }
        }
        installTask = nil
    }

    private func updateInstallTask(id: UUID, _ update: (inout ProjectInstallTaskState) -> Void) {
        guard var state = activeInstallTask, state.id == id else { return }
        update(&state)
        activeInstallTask = state
    }
}
