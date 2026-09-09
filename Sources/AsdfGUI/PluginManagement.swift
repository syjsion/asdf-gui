import Foundation
import Observation

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
        start(kind: .add, pluginName: name, appModel: appModel) { service, executable, output in
            try await service.addPlugin(executable: executable, name: name, gitURL: gitURL, onOutput: output)
        }
    }

    func updatePlugin(_ plugin: AsdfPlugin, appModel: AppModel) {
        start(kind: .update, pluginName: plugin.name, appModel: appModel) { service, executable, output in
            try await service.updatePlugin(executable: executable, name: plugin.name, onOutput: output)
        }
    }

    func updateAllPlugins(appModel: AppModel) {
        start(kind: .updateAll, pluginName: nil, appModel: appModel) { service, executable, output in
            try await service.updateAllPlugins(executable: executable, onOutput: output)
        }
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
        start(kind: .remove, pluginName: impact.plugin.name, appModel: appModel) { service, executable, output in
            try await service.removePlugin(executable: executable, name: impact.plugin.name, onOutput: output)
        }
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

    private func start(
        kind: PluginOperationKind,
        pluginName: String?,
        appModel: AppModel,
        operation: @escaping @Sendable (AsdfService, URL, @escaping @Sendable (AsdfOutputEvent) -> Void) async throws -> AsdfCommandResult
    ) {
        guard !isBusy, !appModel.hasActiveOperation else {
            errorMessage = "Another asdf operation is currently running."
            return
        }
        guard let executable = appModel.executableURL else {
            errorMessage = "asdf executable is not available."
            return
        }

        errorMessage = nil
        let id = UUID()
        let subject = pluginName ?? "installed plugins"
        activeOperation = PluginOperationTaskState(
            id: id,
            kind: kind,
            pluginName: pluginName,
            status: .running,
            log: "\(kind.verb) \(subject)\n",
            errorMessage: nil
        )

        operationTask = Task { [weak self, weak appModel] in
            guard let self, let appModel else { return }
            do {
                _ = try await operation(service, executable) { [weak self] event in
                    Task { [weak self] in
                        await self?.append(event.text, id: id)
                    }
                }
                await self.finish(id: id, status: .succeeded, error: nil)
                await appModel.refresh()
                if let pluginName, appModel.versionBrowserTool == pluginName,
                   !appModel.plugins.contains(where: { $0.name == pluginName }) {
                    appModel.resetVersionBrowser()
                }
            } catch is CancellationError {
                await self.finish(id: id, status: .cancelled, error: nil)
            } catch {
                await self.append("\n✗ \(error.localizedDescription)\n", id: id)
                await self.finish(id: id, status: .failed, error: error.localizedDescription)
            }
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
