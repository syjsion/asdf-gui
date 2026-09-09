import Foundation
import Observation

enum DiagnosticAction: String, CaseIterable, Identifiable {
    case info
    case wherePath
    case which
    case reshim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: "Info"
        case .wherePath: "Where"
        case .which: "Which"
        case .reshim: "Reshim"
        }
    }

    var commandSummary: String {
        switch self {
        case .info: "asdf info"
        case .wherePath: "asdf where <tool> [version]"
        case .which: "asdf which <command>"
        case .reshim: "asdf reshim <tool> <version>"
        }
    }
}

enum DiagnosticReportBuilder {
    static func build(asdfVersion: String, executablePath: String, infoOutput: String) -> String {
        """
        asdf GUI Diagnostic Report
        ==========================
        asdf: \(asdfVersion)
        executable: \(executablePath)

        asdf info
        ---------
        \(infoOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }
}

@MainActor
@Observable
final class DiagnosticsModel {
    var action: DiagnosticAction = .info
    var output = ""
    var outputTitle = "No diagnostic run yet"
    var errorMessage: String?
    var isRunning = false
    var installedVersions: [String] = []
    var versionsError: String?

    private let service = AsdfService()

    func loadInstalledVersions(tool: String?, appModel: AppModel) async {
        guard let tool, !tool.isEmpty, let executable = appModel.executableURL else {
            installedVersions = []
            versionsError = nil
            return
        }
        do {
            installedVersions = try await service.installedVersions(executable: executable, tool: tool)
            versionsError = nil
        } catch {
            installedVersions = []
            versionsError = error.localizedDescription
        }
    }

    func runInfo(appModel: AppModel) async {
        await run(title: "asdf info", appModel: appModel) { service, executable in
            try await service.info(executable: executable)
        }
    }

    func runWhere(tool: String, version: String?, appModel: AppModel) async {
        await run(title: "asdf where \(tool)\(version.map { " \($0)" } ?? "")", appModel: appModel) { service, executable in
            try await service.wherePath(executable: executable, tool: tool, version: version)
        }
    }

    func runWhich(command: String, appModel: AppModel) async {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            errorMessage = "Command name is required."
            return
        }
        await run(title: "asdf which \(command)", appModel: appModel) { service, executable in
            try await service.whichPath(executable: executable, command: command)
        }
    }

    func runReshim(tool: String, version: String, appModel: AppModel) async {
        guard !isRunning else { return }
        guard appModel.beginExternalWriteOperation() else {
            errorMessage = "Another asdf write operation is currently running."
            return
        }
        defer { appModel.endExternalWriteOperation() }

        await run(title: "asdf reshim \(tool) \(version)", appModel: appModel) { service, executable in
            let result = try await service.reshim(executable: executable, tool: tool, version: version)
            let combined = [result.stdout, result.stderr]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            return combined.isEmpty ? "Reshim completed successfully." : combined
        }
    }

    func diagnosticReport(appModel: AppModel) async throws -> String {
        guard let executable = appModel.executableURL else {
            throw AsdfError.executableNotFound
        }
        let info = try await service.info(executable: executable)
        return DiagnosticReportBuilder.build(
            asdfVersion: appModel.asdfVersion,
            executablePath: executable.path,
            infoOutput: info
        )
    }

    private func run(
        title: String,
        appModel: AppModel,
        operation: (AsdfService, URL) async throws -> String
    ) async {
        guard !isRunning else { return }
        guard let executable = appModel.executableURL else {
            errorMessage = "asdf executable is not available."
            return
        }

        isRunning = true
        errorMessage = nil
        output = ""
        outputTitle = title
        defer { isRunning = false }

        do {
            output = try await operation(service, executable)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
