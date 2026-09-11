import Foundation
import Observation

struct RuntimePreset: Identifiable, Hashable, Sendable {
    let tool: String
    let displayName: String
    let symbol: String

    var id: String { tool }

    static let popular: [RuntimePreset] = [
        RuntimePreset(tool: "nodejs", displayName: "Node.js", symbol: "server.rack"),
        RuntimePreset(tool: "python", displayName: "Python", symbol: "chevron.left.forwardslash.chevron.right"),
        RuntimePreset(tool: "ruby", displayName: "Ruby", symbol: "diamond"),
        RuntimePreset(tool: "golang", displayName: "Go", symbol: "shippingbox"),
        RuntimePreset(tool: "java", displayName: "Java", symbol: "cup.and.saucer")
    ]
}

enum RuntimeSetupDestination: String, CaseIterable, Identifiable, Sendable {
    case installOnly
    case home
    case project

    var id: String { rawValue }
}

enum RuntimeSetupPhase: Equatable, Sendable {
    case idle
    case loadingCatalog
    case installingPlugin
    case loadingVersions
    case ready
    case installingRuntime
    case completed
    case failed
}

enum RuntimeSetupPlanner {
    static func exactCatalogEntry(
        named tool: String,
        catalog: [AsdfPluginCatalogEntry]
    ) -> AsdfPluginCatalogEntry? {
        catalog.first { $0.name.caseInsensitiveCompare(tool) == .orderedSame }
    }

    static func needsPluginInstall(tool: String, plugins: [AsdfPlugin]) -> Bool {
        !plugins.contains { $0.name.caseInsensitiveCompare(tool) == .orderedSame }
    }

    static func shouldInstallVersion(
        tool: String,
        version: String,
        installedVersionsByTool: [String: [String]]
    ) -> Bool {
        !(installedVersionsByTool[tool]?.contains(version) ?? false)
    }

    static func refreshTools(plugins: [AsdfPlugin]) -> [String] {
        Array(Set(plugins.map(\.name))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

@MainActor
@Observable
final class RuntimeSetupModel {
    var catalog: [AsdfPluginCatalogEntry] = []
    var catalogError: String?
    var selectedTool: String?
    var selectedGitURL: String?
    var availableVersions: [String] = []
    var latestVersion: String?
    var selectedVersion: String?
    var destination: RuntimeSetupDestination = .installOnly
    var selectedProjectPath: String?
    var phase: RuntimeSetupPhase = .idle
    var log = ""
    var errorMessage: String?

    private let service = AsdfService()
    private var operationTask: Task<Void, Never>?
    private let logLimit = 120_000

    var isBusy: Bool {
        switch phase {
        case .loadingCatalog, .installingPlugin, .loadingVersions, .installingRuntime:
            true
        case .idle, .ready, .completed, .failed:
            false
        }
    }

    func loadCatalog(appModel: AppModel, force: Bool = false) async {
        guard force || catalog.isEmpty else { return }
        guard !isBusy || phase == .loadingCatalog else { return }
        guard let executable = appModel.executableURL else {
            catalogError = "asdf executable is not available."
            return
        }

        phase = .loadingCatalog
        catalogError = nil
        do {
            catalog = try await service.pluginCatalog(executable: executable)
            phase = selectedTool == nil ? .idle : .ready
            refreshSelectedCatalogMetadata()
        } catch is CancellationError {
            phase = .idle
        } catch {
            catalogError = error.localizedDescription
            phase = selectedTool == nil ? .idle : .ready
        }
    }

    func select(tool: String, appModel: AppModel) {
        guard !isBusy else { return }
        let normalized = tool.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        selectedTool = normalized
        selectedGitURL = RuntimeSetupPlanner.exactCatalogEntry(named: normalized, catalog: catalog)?.url
        availableVersions = []
        latestVersion = nil
        selectedVersion = nil
        errorMessage = nil
        log = ""
        phase = .idle

        if selectedProjectPath == nil {
            selectedProjectPath = appModel.projects.first?.path
        }

        if !RuntimeSetupPlanner.needsPluginInstall(tool: normalized, plugins: appModel.plugins) {
            Task { [weak self] in
                await self?.loadVersions(appModel: appModel)
            }
        }
    }

    func installPluginAndContinue(appModel: AppModel) {
        guard let tool = selectedTool, !isBusy else { return }
        guard RuntimeSetupPlanner.needsPluginInstall(tool: tool, plugins: appModel.plugins) else {
            Task { [weak self] in await self?.loadVersions(appModel: appModel) }
            return
        }
        guard let executable = appModel.executableURL else {
            fail("asdf executable is not available.")
            return
        }
        guard appModel.beginExternalWriteOperation() else {
            fail("Another asdf operation is currently running.")
            return
        }

        phase = .installingPlugin
        errorMessage = nil
        append("Installing plugin \(tool)…\n")
        let gitURL = selectedGitURL

        operationTask = Task { [weak self] in
            guard let self else {
                appModel.endExternalWriteOperation()
                return
            }
            defer { appModel.endExternalWriteOperation() }
            do {
                _ = try await self.service.addPlugin(
                    executable: executable,
                    name: tool,
                    gitURL: gitURL
                ) { [weak self] event in
                    Task { @MainActor [weak self] in self?.append(event.text) }
                }
                self.append("\n✓ Plugin \(tool) installed.\n")
                await appModel.refresh()
                await self.loadVersions(appModel: appModel)
            } catch is CancellationError {
                self.phase = .idle
                self.append("\nPlugin installation cancelled.\n")
            } catch {
                self.fail(error.localizedDescription)
            }
            self.operationTask = nil
        }
    }

    func loadVersions(appModel: AppModel) async {
        guard let tool = selectedTool,
              let executable = appModel.executableURL else { return }
        guard phase != .installingRuntime && phase != .installingPlugin else { return }
        guard !RuntimeSetupPlanner.needsPluginInstall(tool: tool, plugins: appModel.plugins) else {
            phase = .idle
            return
        }

        phase = .loadingVersions
        errorMessage = nil
        var partialErrors: [String] = []

        do {
            latestVersion = try await service.latestVersion(executable: executable, tool: tool)
        } catch is CancellationError {
            phase = .idle
            return
        } catch {
            partialErrors.append("Latest version: \(error.localizedDescription)")
        }

        do {
            availableVersions = try await service.availableVersions(executable: executable, tool: tool)
        } catch is CancellationError {
            phase = .idle
            return
        } catch {
            partialErrors.append("Available versions: \(error.localizedDescription)")
        }

        do {
            let installed = try await service.installedVersions(executable: executable, tool: tool)
            appModel.installedVersionsByTool[tool] = installed
        } catch is CancellationError {
            phase = .idle
            return
        } catch {
            partialErrors.append("Installed versions: \(error.localizedDescription)")
        }

        if selectedVersion == nil {
            selectedVersion = latestVersion ?? availableVersions.last
        }
        if !partialErrors.isEmpty {
            errorMessage = partialErrors.joined(separator: "\n")
        }
        phase = .ready
    }

    func installSelectedRuntime(appModel: AppModel) {
        guard !isBusy,
              let tool = selectedTool,
              let version = selectedVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else { return }
        guard let executable = appModel.executableURL else {
            fail("asdf executable is not available.")
            return
        }
        guard appModel.beginExternalWriteOperation() else {
            fail("Another asdf operation is currently running.")
            return
        }

        phase = .installingRuntime
        errorMessage = nil
        append("\nPreparing \(tool) \(version)…\n")
        let destination = destination
        let projectPath = selectedProjectPath

        operationTask = Task { [weak self] in
            guard let self else {
                appModel.endExternalWriteOperation()
                return
            }
            defer { appModel.endExternalWriteOperation() }

            do {
                let installedVersions = try await self.service.installedVersions(
                    executable: executable,
                    tool: tool
                )
                appModel.installedVersionsByTool[tool] = installedVersions

                if !installedVersions.contains(version) {
                    self.append("\n$ asdf install \(tool) \(version)\n")
                    _ = try await self.service.installVersion(
                        executable: executable,
                        tool: tool,
                        version: version
                    ) { [weak self] event in
                        Task { @MainActor [weak self] in self?.append(event.text) }
                    }
                    self.append("\n✓ Installed \(tool) \(version).\n")
                } else {
                    self.append("\n✓ \(tool) \(version) is already installed; skipping download.\n")
                }

                switch destination {
                case .installOnly:
                    break
                case .home:
                    self.append("\n$ asdf set -u \(tool) \(version)\n")
                    _ = try await self.service.setVersion(
                        executable: executable,
                        tool: tool,
                        versions: [version],
                        scope: .home
                    )
                case .project:
                    guard let projectPath,
                          appModel.projects.contains(where: { $0.path == projectPath }) else {
                        throw AsdfError.commandFailed("Choose a managed project before configuring this runtime.")
                    }
                    self.append("\n$ asdf set \(tool) \(version)\n")
                    _ = try await self.service.setVersion(
                        executable: executable,
                        tool: tool,
                        versions: [version],
                        scope: .project(URL(fileURLWithPath: projectPath, isDirectory: true))
                    )
                }

                await appModel.refresh()
                self.phase = .completed
                self.append("\n✓ Runtime setup complete.\n")
            } catch is CancellationError {
                self.phase = .ready
                self.append("\nRuntime setup cancelled.\n")
            } catch {
                self.fail(error.localizedDescription)
            }
            self.operationTask = nil
        }
    }

    func cancel() {
        operationTask?.cancel()
    }

    func startOver(appModel: AppModel) {
        operationTask?.cancel()
        selectedTool = nil
        selectedGitURL = nil
        availableVersions = []
        latestVersion = nil
        selectedVersion = nil
        destination = .installOnly
        selectedProjectPath = appModel.projects.first?.path
        phase = .idle
        log = ""
        errorMessage = nil
    }

    private func refreshSelectedCatalogMetadata() {
        guard let selectedTool else { return }
        selectedGitURL = RuntimeSetupPlanner.exactCatalogEntry(named: selectedTool, catalog: catalog)?.url
    }

    private func fail(_ message: String) {
        errorMessage = message
        phase = .failed
        append("\n✗ \(message)\n")
    }

    private func append(_ text: String) {
        let combined = log + text
        if combined.count > logLimit {
            log = "… older output truncated …\n" + String(combined.suffix(logLimit - 64))
        } else {
            log = combined
        }
    }
}
