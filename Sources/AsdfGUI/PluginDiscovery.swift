import Foundation
import Observation

@MainActor
@Observable
final class PluginDiscoveryModel {
    var catalog: [AsdfPluginCatalogEntry] = []
    var isLoading = false
    var errorMessage: String?

    private let service = AsdfService()

    func load(appModel: AppModel) async {
        guard let executable = appModel.executableURL else {
            catalog = []
            errorMessage = "asdf executable is not available."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            catalog = try await service.pluginCatalog(executable: executable)
        } catch {
            catalog = []
            errorMessage = error.localizedDescription
        }
    }
}
