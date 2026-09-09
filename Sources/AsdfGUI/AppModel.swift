import Foundation
import Observation

struct AsdfPlugin: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let url: String?
}

struct AsdfCommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
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
    var isLoading = false
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
        } catch {
            executableURL = nil
            asdfVersion = "Not detected"
            plugins = []
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
    }

    func removeProject(_ project: ManagedProject) {
        projects.removeAll { $0.id == project.id }
        preferences.setProjects(projects)
        refreshProjects()
    }

    func refreshProjects() {
        projectSnapshots = projects.map { projectService.snapshot(for: $0) }
    }
}
