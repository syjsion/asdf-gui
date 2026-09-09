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

    var versionBrowserTool: String?
    var versionBrowserInstalledVersions: [String] = []
    var versionBrowserAvailableVersions: [String] = []
    var versionBrowserLatestVersion: String?
    var versionBrowserErrors: [String] = []
    var isLoadingVersionBrowser = false

    var activeInstallTask: ProjectInstallTaskState?
    var activeVersionOperation: VersionOperationTaskState?
    var isLoading = false
    var isRefreshingVersionStatus = false
    var errorMessage: String?

    var hasActiveOperation: Bool {
        activeInstallTask?.isRunning == true || activeVersionOperation?.isRunning == true
    }

    private let service = AsdfService()
    private let projectService = ProjectService()
    private let preferences = PreferencesStore()
    private let taskLogLimit = 200_000
    private var installTask: Task<Void, Never>?
    private var versionOperationTask: Task<Void, Never>?
    private var versionBrowserRequestID: UUID?

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
            resetVersionBrowser()
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

    func loadVersionBrowser(tool: String) async {
        guard let executable = executableURL else {
            resetVersionBrowser()
            versionBrowserTool = tool
            versionBrowserErrors = ["asdf executable is not available."]
            return
        }

        let requestID = UUID()
        versionBrowserRequestID = requestID
        versionBrowserTool = tool
        versionBrowserInstalledVersions = []
        versionBrowserAvailableVersions = []
        versionBrowserLatestVersion = nil
        versionBrowserErrors = []
        isLoadingVersionBrowser = true

        defer {
            if versionBrowserRequestID == requestID {
                isLoadingVersionBrowser = false
            }
        }

        do {
            let installed = try await service.installedVersions(executable: executable, tool: tool)
            guard versionBrowserRequestID == requestID else { return }
            versionBrowserInstalledVersions = installed
            installedVersionsByTool[tool] = installed
        } catch is CancellationError {
            return
        } catch {
            appendVersionBrowserError("Installed versions: \(error.localizedDescription)", requestID: requestID)
        }

        do {
            let latest = try await service.latestVersion(executable: executable, tool: tool)
            guard versionBrowserRequestID == requestID else { return }
            versionBrowserLatestVersion = latest
        } catch is CancellationError {
            return
        } catch {
            appendVersionBrowserError("Latest version: \(error.localizedDescription)", requestID: requestID)
        }

        do {
            let available = try await service.availableVersions(executable: executable, tool: tool)
            guard versionBrowserRequestID == requestID else { return }
            versionBrowserAvailableVersions = available
        } catch is CancellationError {
            return
        } catch {
            appendVersionBrowserError("Available versions: \(error.localizedDescription)", requestID: requestID)
        }
    }

    func resetVersionBrowser() {
        versionBrowserRequestID = nil
        versionBrowserTool = nil
        versionBrowserInstalledVersions = []
        versionBrowserAvailableVersions = []
        versionBrowserLatestVersion = nil
        versionBrowserErrors = []
        isLoadingVersionBrowser = false
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

    func projectsUsing(tool: String, version: String) -> [ManagedProject] {
        VersionUsageInspector.projectsUsing(
            tool: tool,
            version: version,
            snapshots: projectSnapshots
        )
    }

    func installMissing(for snapshot: ProjectSnapshot) {
        guard !hasActiveOperation, executableURL != nil else { return }

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

    func installVersionFromBrowser(tool: String, version: String) {
        startVersionOperation(kind: .install, tool: tool, version: version)
    }

    func uninstallVersionFromBrowser(tool: String, version: String) {
        startVersionOperation(kind: .uninstall, tool: tool, version: version)
    }

    func cancelVersionOperation() {
        guard let state = activeVersionOperation, state.isRunning else { return }
        appendVersionOperationLog("\nCancelling…\n", taskID: state.id)
        versionOperationTask?.cancel()
    }

    func dismissVersionOperation() {
        guard activeVersionOperation?.isRunning != true else { return }
        activeVersionOperation = nil
    }

    private func appendVersionBrowserError(_ message: String, requestID: UUID) {
        guard versionBrowserRequestID == requestID else { return }
        versionBrowserErrors.append(message)
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

    private func startVersionOperation(kind: VersionOperationKind, tool: String, version: String) {
        guard !hasActiveOperation, executableURL != nil else { return }

        let taskID = UUID()
        let action = kind == .install ? "Installing" : "Uninstalling"
        activeVersionOperation = VersionOperationTaskState(
            id: taskID,
            kind: kind,
            tool: tool,
            version: version,
            status: .running,
            log: "\(action) \(tool) \(version)\n",
            errorMessage: nil
        )

        versionOperationTask = Task { [weak self] in
            await self?.runVersionOperation(id: taskID, kind: kind, tool: tool, version: version)
        }
    }

    private func runVersionOperation(
        id: UUID,
        kind: VersionOperationKind,
        tool: String,
        version: String
    ) async {
        guard let executable = executableURL else {
            finishVersionOperation(id: id, status: .failed, error: "asdf executable is not available.")
            return
        }

        let command = kind == .install ? "install" : "uninstall"
        appendVersionOperationLog("\n$ asdf \(command) \(tool) \(version)\n", taskID: id)

        do {
            switch kind {
            case .install:
                _ = try await service.installVersion(
                    executable: executable,
                    tool: tool,
                    version: version
                ) { [weak self] event in
                    Task { [weak self] in
                        await self?.appendVersionOperationOutput(event, taskID: id)
                    }
                }
            case .uninstall:
                _ = try await service.uninstallVersion(
                    executable: executable,
                    tool: tool,
                    version: version
                ) { [weak self] event in
                    Task { [weak self] in
                        await self?.appendVersionOperationOutput(event, taskID: id)
                    }
                }
            }

            appendVersionOperationLog(
                "\n✓ \(kind == .install ? "Installed" : "Uninstalled") \(tool) \(version)\n",
                taskID: id
            )
            finishVersionOperation(id: id, status: .succeeded, error: nil)
            await refreshVersionStateAfterOperation(tool: tool)
        } catch is CancellationError {
            finishVersionOperation(id: id, status: .cancelled, error: nil)
        } catch {
            appendVersionOperationLog("\n✗ \(error.localizedDescription)\n", taskID: id)
            finishVersionOperation(id: id, status: .failed, error: error.localizedDescription)
        }
    }

    private func refreshVersionStateAfterOperation(tool: String) async {
        await refreshInstalledVersions()
        guard let executable = executableURL else { return }

        do {
            let installed = try await service.installedVersions(executable: executable, tool: tool)
            installedVersionsByTool[tool] = installed
            if versionBrowserTool == tool {
                versionBrowserInstalledVersions = installed
            }
        } catch {
            if versionBrowserTool == tool {
                versionBrowserErrors.append("Installed versions after operation: \(error.localizedDescription)")
            }
        }
    }

    private func appendInstallOutput(_ event: AsdfOutputEvent, taskID: UUID) {
        appendInstallLog(event.text, taskID: taskID)
    }

    private func appendInstallLog(_ text: String, taskID: UUID) {
        updateInstallTask(id: taskID) { state in
            state.log = cappedLog(state.log + text)
        }
    }

    private func finishInstallTask(id: UUID, status: ProjectInstallTaskStatus, error: String?) {
        updateInstallTask(id: id) { state in
            state.status = status
            state.currentItem = nil
            state.errorMessage = error
            switch status {
            case .succeeded:
                state.log = cappedLog(state.log + "\nAll planned runtimes installed.\n")
            case .cancelled:
                state.log = cappedLog(state.log + "\nInstallation cancelled.\n")
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

    private func appendVersionOperationOutput(_ event: AsdfOutputEvent, taskID: UUID) {
        appendVersionOperationLog(event.text, taskID: taskID)
    }

    private func appendVersionOperationLog(_ text: String, taskID: UUID) {
        updateVersionOperation(id: taskID) { state in
            state.log = cappedLog(state.log + text)
        }
    }

    private func finishVersionOperation(id: UUID, status: VersionOperationStatus, error: String?) {
        updateVersionOperation(id: id) { state in
            state.status = status
            state.errorMessage = error
            switch status {
            case .succeeded:
                state.log = cappedLog(state.log + "\nVersion operation complete.\n")
            case .cancelled:
                state.log = cappedLog(state.log + "\nVersion operation cancelled.\n")
            case .failed, .running:
                break
            }
        }
        versionOperationTask = nil
    }

    private func updateVersionOperation(id: UUID, _ update: (inout VersionOperationTaskState) -> Void) {
        guard var state = activeVersionOperation, state.id == id else { return }
        update(&state)
        activeVersionOperation = state
    }

    private func cappedLog(_ value: String) -> String {
        guard value.count > taskLogLimit else { return value }
        let retained = String(value.suffix(taskLogLimit - 64))
        return "… older output truncated …\n" + retained
    }
}
