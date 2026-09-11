import Foundation

@MainActor
extension AppModel {
    func refreshAllInstalledPluginVersions() async {
        guard let executable = executableURL else { return }

        let service = AsdfService()
        var versions = installedVersionsByTool
        var errors = versionLookupErrors

        for tool in RuntimeSetupPlanner.refreshTools(plugins: plugins) {
            do {
                versions[tool] = try await service.installedVersions(
                    executable: executable,
                    tool: tool
                )
                errors.removeValue(forKey: tool)
            } catch is CancellationError {
                return
            } catch {
                errors[tool] = error.localizedDescription
            }
        }

        installedVersionsByTool = versions
        versionLookupErrors = errors
    }
}
