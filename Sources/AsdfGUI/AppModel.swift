import Foundation
import Observation

struct AsdfPlugin: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let url: String?
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
    var isLoading = false
    var isRefreshingVersionStatus = false
    var errorMessage: String?

    private let service = AsdfService()
    private let projectService = ProjectService()
    private let preferences = PreferencesStore()

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
}
