import Foundation
import Observation

enum PluginCatalogResolver {
    static func exactEntry(
        for tool: String,
        in catalog: [AsdfPluginCatalogEntry]
    ) -> AsdfPluginCatalogEntry? {
        catalog.first { entry in
            entry.name.compare(tool, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}

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
