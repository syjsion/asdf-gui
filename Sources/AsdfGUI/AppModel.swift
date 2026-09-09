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
    var executableURL: URL?
    var asdfVersion = "Not detected"
    var plugins: [AsdfPlugin] = []
    var isLoading = false
    var errorMessage: String?

    private let service = AsdfService()

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let executable = try service.locateExecutable()
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
}
