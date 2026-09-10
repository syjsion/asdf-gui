import Foundation
import Observation

struct ResolutionContext: Identifiable, Hashable {
    let project: ManagedProject?

    var id: String { project?.id ?? "__home__" }
    var title: String { project?.name ?? "Home" }
    var directory: URL { project?.url ?? FileManager.default.homeDirectoryForCurrentUser }
    var detail: String { project?.path ?? FileManager.default.homeDirectoryForCurrentUser.path }
}

@MainActor
@Observable
final class ResolutionModel {
    var currentEntries: [AsdfCurrentEntry] = []
    var currentError: String?
    var isLoadingCurrent = false

    var resolvedCommandPath: String?
    var shimProviders: [AsdfShimProvider] = []
    var commandError: String?
    var isLoadingCommand = false

    private let service = AsdfService()

    func loadCurrent(
        appModel: AppModel,
        context: ResolutionContext,
        tool: String?
    ) async {
        guard let executable = appModel.executableURL else {
            currentEntries = []
            currentError = "asdf executable is not available."
            return
        }

        isLoadingCurrent = true
        currentError = nil
        defer { isLoadingCurrent = false }

        do {
            currentEntries = try await service.current(
                executable: executable,
                tool: tool,
                currentDirectory: context.directory
            )
        } catch {
            currentEntries = []
            currentError = error.localizedDescription
        }
    }

    func resolveCommand(
        _ command: String,
        appModel: AppModel,
        context: ResolutionContext
    ) async {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            commandError = "Enter a command such as node, npm, python, ruby, or yarn."
            return
        }
        guard let executable = appModel.executableURL else {
            commandError = "asdf executable is not available."
            return
        }

        isLoadingCommand = true
        commandError = nil
        resolvedCommandPath = nil
        shimProviders = []
        defer { isLoadingCommand = false }

        async let providersResult = service.shimVersions(executable: executable, command: command)
        async let pathResult = service.whichPathInDirectory(
            executable: executable,
            command: command,
            currentDirectory: context.directory
        )

        do {
            shimProviders = try await providersResult
        } catch {
            commandError = "Shim providers: \(error.localizedDescription)"
        }

        do {
            resolvedCommandPath = try await pathResult
        } catch {
            let prefix = commandError.map { $0 + "\n" } ?? ""
            commandError = prefix + "Resolved executable: \(error.localizedDescription)"
        }
    }
}

extension AsdfService {
    func whichPathInDirectory(
        executable: URL,
        command: String,
        currentDirectory: URL
    ) async throws -> String {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw AsdfError.commandFailed("A command is required.")
        }

        let result = try await AsdfCommandRunner().run(
            executable: executable,
            arguments: ["which", command],
            currentDirectory: currentDirectory
        )
        guard result.exitCode == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AsdfError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
