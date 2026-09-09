import Foundation

enum VersionSelectionError: LocalizedError {
    case operationInProgress
    case executableUnavailable

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return "Another asdf write operation is currently running. Finish or cancel it before changing a configured version."
        case .executableUnavailable:
            return "asdf executable is not available. Configure it in Settings first."
        }
    }
}

@MainActor
extension AppModel {
    func loadInstalledVersionsForSelection(tool: String) async throws -> [String] {
        guard let executableURL else { throw VersionSelectionError.executableUnavailable }
        let installed = try await AsdfService().installedVersions(executable: executableURL, tool: tool)
        installedVersionsByTool[tool] = installed
        return installed
    }

    func setProjectVersion(tool: String, version: String, project: ManagedProject) async throws {
        guard !hasActiveOperation else { throw VersionSelectionError.operationInProgress }
        guard let executableURL else { throw VersionSelectionError.executableUnavailable }

        _ = try await AsdfService().setVersion(
            executable: executableURL,
            tool: tool,
            versions: [version],
            scope: .project(project.url)
        )

        refreshProjects()
        await refreshInstalledVersions()
    }

    func setHomeVersion(tool: String, version: String) async throws {
        guard !hasActiveOperation else { throw VersionSelectionError.operationInProgress }
        guard let executableURL else { throw VersionSelectionError.executableUnavailable }

        _ = try await AsdfService().setVersion(
            executable: executableURL,
            tool: tool,
            versions: [version],
            scope: .home
        )
    }

    func configuredVersions(tool: String, project: ManagedProject) -> [String] {
        projectSnapshots
            .first(where: { $0.project.id == project.id })?
            .requirements
            .first(where: { $0.tool == tool })?
            .versions ?? []
    }
}
