import Foundation
import Observation

typealias PluginOutputHandler = @Sendable (AsdfOutputEvent) -> Void

enum PluginOperationKind: Hashable {
    case add
    case update
    case updateAll
    case remove

    var verb: String {
        switch self {
        case .add: "Add"
        case .update: "Update"
        case .updateAll: "Update all"
        case .remove: "Remove"
        }
    }
}

enum PluginOperationStatus: Hashable {
    case running
    case succeeded
    case failed
    case cancelled
}

private enum PluginOperationRequest: Hashable {
    case add(name: String, gitURL: String?)
    case update(name: String, gitRef: String?)
    case updateAll
    case remove(name: String)

    var kind: PluginOperationKind {
        switch self {
        case .add: .add
        case .update: .update
        case .updateAll: .updateAll
        case .remove: .remove
        }
    }

    var pluginName: String? {
        switch self {
        case .add(let name, _), .update(let name, _), .remove(let name): name
        case .updateAll: nil
        }
    }
}

struct PluginOperationTaskState: Identifiable {
    let id: UUID
    let kind: PluginOperationKind
    let pluginName: String?
    var status: PluginOperationStatus
    var log: String
    var errorMessage: String?

    var isRunning: Bool { status == .running }
}

struct PluginRemovalImpact: Identifiable, Hashable {
    let plugin: AsdfPlugin
    let installedVersions: [String]
    let projects: [ManagedProject]

    var id: String { plugin.name }
}

enum PluginRemovalInspector {
    static func projectsReferencing(pluginName: String, snapshots: [ProjectSnapshot]) -> [ManagedProject] {
        snapshots
            .filter { snapshot in
                snapshot.requirements.contains { $0.tool == pluginName }
            }
            .map(\.project)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
@Observable
final class PluginManagementModel {
    var activeOperation: PluginOperationTaskState?
    var removalImpact: PluginRemovalImpact?
    var isPreparingRemoval = false
    var errorMessage: String?

    private let service = AsdfService()
    private let logLimit = 200_000
    private var operationTask: Task<Void, Never>?

    var isBusy: Bool {
        activeOperation?.isRunning == true || isPreparingRemoval
    }

    func addPlugin(name: String, gitURL: String?, appModel: AppModel) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Plugin name is required."
            return
        }
        if appModel.plugins.contains(where: { $0.name == name }) {
            errorMessage = "The \(name) plugin is already installed."
            return
        }
        start(request: .add(name: name, gitURL: gitURL), appModel: appModel)
    }

    func updatePlugin(_ plugin: AsdfPlugin, appModel: AppModel) {
        start(request: .update(name: plugin.name, gitRef: nil), appModel: appModel)
    }

    func updateAllPlugins(appModel: AppModel) {
        start(request: .updateAll, appModel: appModel)
    }

    func prepareRemoval(of plugin: AsdfPlugin, appModel: AppModel) async {
        guard !isBusy, !appModel.hasActiveOperation else {
            errorMessage = "Another asdf operation is currently running."
            return
        }
        guard let executable = appModel.executableURL else {
            errorMessage = "asdf executable is not available."
            return
        }

        isPreparingRemoval = true
        errorMessage = nil
        defer { isPreparingRemoval = false }

        do {
            let installedVersions = try await service.installedVersions(executable: executable, tool: plugin.name)
            let projects = PluginRemovalInspector.projectsReferencing(
                pluginName: plugin.name,
                snapshots: appModel.projectSnapshots
            )
            removalImpact = PluginRemovalImpact(
                plugin: plugin,
                installedVersions: installedVersions,
                projects: projects
            )
        } catch {
            errorMessage = "Could not determine removal impact: \(error.localizedDescription)"
        }
    }

    func confirmRemoval(appModel: AppModel) {
        guard let impact = removalImpact else { return }
        removalImpact = nil
        start(request: .remove(name: impact.plugin.name), appModel: appModel)
    }

    func cancelRemoval() {
        removalImpact = nil
    }

    func cancelOperation() {
        guard activeOperation?.isRunning == true else { return }
        operationTask?.cancel()
    }

    func dismissOperation() {
        guard activeOperation?.isRunning != true else { return }
        activeOperation = nil
    }

    private func start(request: PluginOperationRequest, appModel: AppModel) {
        guard !isBusy else { return }
        guard let executable = appModel.executableURL else {
            errorMessage = "asdf executable is not available."
            return
        }
        guard appModel.beginExternalWriteOperation() else {
            errorMessage = "Another asdf write operation is currently running."
            return
        }

        errorMessage = nil
        let id = UUID()
        let subject = request.pluginName ?? "installed plugins"
        activeOperation = PluginOperationTaskState(
            id: id,
            kind: request.kind,
            pluginName: request.pluginName,
            status: .running,
            log: "\(request.kind.verb) \(subject)\n",
            errorMessage: nil
        )

        operationTask = Task { [weak self] in
            guard let self else {
                appModel.endExternalWriteOperation()
                return
            }
            defer { appModel.endExternalWriteOperation() }

            let output: PluginOutputHandler = { [weak self] event in
                Task { [weak self] in
                    await self?.append(event.text, id: id)
                }
            }

            do {
                _ = try await self.execute(
                    request: request,
                    executable: executable,
                    output: output
                )
                self.finish(id: id, status: .succeeded, error: nil)
                await appModel.refresh()
                if let pluginName = request.pluginName,
                   appModel.versionBrowserTool == pluginName,
                   !appModel.plugins.contains(where: { $0.name == pluginName }) {
                    appModel.resetVersionBrowser()
                }
            } catch is CancellationError {
                self.finish(id: id, status: .cancelled, error: nil)
            } catch {
                self.append("\n✗ \(error.localizedDescription)\n", id: id)
                self.finish(id: id, status: .failed, error: error.localizedDescription)
            }
        }
    }

    private func execute(
        request: PluginOperationRequest,
        executable: URL,
        output: @escaping PluginOutputHandler
    ) async throws -> AsdfCommandResult {
        switch request {
        case .add(let name, let gitURL):
            return try await service.addPlugin(
                executable: executable,
                name: name,
                gitURL: gitURL,
                onOutput: output
            )
        case .update(let name, let gitRef):
            return try await service.updatePlugin(
                executable: executable,
                name: name,
                gitRef: gitRef,
                onOutput: output
            )
        case .updateAll:
            return try await service.updateAllPlugins(executable: executable, onOutput: output)
        case .remove(let name):
            return try await service.removePlugin(executable: executable, name: name, onOutput: output)
        }
    }

    private func append(_ text: String, id: UUID) {
        guard var state = activeOperation, state.id == id else { return }
        state.log = capped(state.log + text)
        activeOperation = state
    }

    private func finish(id: UUID, status: PluginOperationStatus, error: String?) {
        guard var state = activeOperation, state.id == id else { return }
        state.status = status
        state.errorMessage = error
        switch status {
        case .succeeded:
            state.log = capped(state.log + "\n✓ Plugin operation complete.\n")
        case .cancelled:
            state.log = capped(state.log + "\nPlugin operation cancelled.\n")
        case .failed, .running:
            break
        }
        activeOperation = state
        operationTask = nil
    }

    private func capped(_ value: String) -> String {
        guard value.count > logLimit else { return value }
        return "… older output truncated …\n" + String(value.suffix(logLimit - 64))
    }
}
