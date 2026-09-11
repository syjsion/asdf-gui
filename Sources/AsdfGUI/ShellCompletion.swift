import Foundation
import Observation

enum ShellCompletionStatus: Hashable, Sendable {
    case notConfigured
    case configured
    case needsUpdate
}

struct ShellCompletionPlan: Sendable {
    let shell: SupportedShell
    let configurationURL: URL
    let executableURL: URL
    let managedBlock: String
    let originalConfigurationContents: String
    let proposedConfigurationContents: String
    let completionFileURL: URL?
    let originalCompletionContents: String?
    let proposedCompletionContents: String?
    let status: ShellCompletionStatus
}

enum ShellCompletionError: LocalizedError, Equatable {
    case malformedManagedBlock
    case configurationChanged
    case completionFileChanged
    case missingCompletionScript

    var errorDescription: String? {
        switch self {
        case .malformedManagedBlock:
            return "The shell configuration contains an incomplete asdf GUI completion block. Fix or remove the incomplete markers before continuing."
        case .configurationChanged:
            return "The shell configuration changed after the completion preview was generated. Refresh before applying changes."
        case .completionFileChanged:
            return "The generated completion file changed after the preview was generated. Refresh before applying changes."
        case .missingCompletionScript:
            return "asdf completion zsh returned no completion script."
        }
    }
}

struct ShellCompletionService {
    static let beginMarker = "# >>> asdf GUI shell completions >>>"
    static let endMarker = "# <<< asdf GUI shell completions <<<"

    private let fileManager: FileManager
    private let homeDirectory: URL
    private let environment: [String: String]

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    func configurationURL(for shell: SupportedShell) -> URL {
        switch shell {
        case .zsh:
            return homeDirectory.appendingPathComponent(".zshrc")
        case .bash:
            return homeDirectory.appendingPathComponent(".bashrc")
        }
    }

    func completionDirectoryURL() -> URL {
        if let override = environment["ASDF_DATA_DIR"], override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("completions", isDirectory: true)
        }
        return homeDirectory.appendingPathComponent(".asdf/completions", isDirectory: true)
    }

    func plan(
        shell: SupportedShell,
        executableURL: URL,
        completionScript: String?
    ) throws -> ShellCompletionPlan {
        let configurationURL = configurationURL(for: shell)
        let originalConfiguration = try readTextIfExists(configurationURL) ?? ""
        let completionDirectory = completionDirectoryURL()
        let block = Self.managedBlock(
            shell: shell,
            executableURL: executableURL,
            completionDirectoryURL: completionDirectory
        )
        let range = try managedRange(in: originalConfiguration)

        let proposedConfiguration: String
        let configurationMatches: Bool
        if let range {
            let existing = String(originalConfiguration[range])
            configurationMatches = existing == block
            proposedConfiguration = configurationMatches
                ? originalConfiguration
                : originalConfiguration.replacingCharacters(in: range, with: block)
        } else {
            configurationMatches = false
            proposedConfiguration = Self.appending(block: block, to: originalConfiguration)
        }

        var completionFileURL: URL?
        var originalCompletionContents: String?
        var proposedCompletionContents: String?
        var completionMatches = true

        if shell == .zsh {
            guard let completionScript,
                  !completionScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ShellCompletionError.missingCompletionScript
            }
            let normalizedScript = completionScript.hasSuffix("\n") ? completionScript : completionScript + "\n"
            let fileURL = completionDirectory.appendingPathComponent("_asdf")
            completionFileURL = fileURL
            originalCompletionContents = try readTextIfExists(fileURL)
            proposedCompletionContents = normalizedScript
            completionMatches = originalCompletionContents == normalizedScript
        }

        let status: ShellCompletionStatus
        if configurationMatches && completionMatches {
            status = .configured
        } else if range != nil || originalCompletionContents != nil {
            status = .needsUpdate
        } else {
            status = .notConfigured
        }

        return ShellCompletionPlan(
            shell: shell,
            configurationURL: configurationURL,
            executableURL: executableURL,
            managedBlock: block,
            originalConfigurationContents: originalConfiguration,
            proposedConfigurationContents: proposedConfiguration,
            completionFileURL: completionFileURL,
            originalCompletionContents: originalCompletionContents,
            proposedCompletionContents: proposedCompletionContents,
            status: status
        )
    }

    func apply(_ plan: ShellCompletionPlan) throws {
        let currentConfiguration = try readTextIfExists(plan.configurationURL) ?? ""
        guard currentConfiguration == plan.originalConfigurationContents else {
            throw ShellCompletionError.configurationChanged
        }

        if let completionFileURL = plan.completionFileURL {
            let currentCompletion = try readTextIfExists(completionFileURL)
            guard currentCompletion == plan.originalCompletionContents else {
                throw ShellCompletionError.completionFileChanged
            }
        }

        var wroteCompletion = false
        do {
            if let completionFileURL = plan.completionFileURL,
               let completionContents = plan.proposedCompletionContents {
                try write(completionContents, to: completionFileURL)
                wroteCompletion = true
            }
            try write(plan.proposedConfigurationContents, to: plan.configurationURL)
        } catch {
            if wroteCompletion, let completionFileURL = plan.completionFileURL {
                restoreCompletionFile(plan.originalCompletionContents, at: completionFileURL)
            }
            throw error
        }
    }

    func remove(_ plan: ShellCompletionPlan) throws {
        let currentConfiguration = try readTextIfExists(plan.configurationURL) ?? ""
        guard currentConfiguration == plan.originalConfigurationContents else {
            throw ShellCompletionError.configurationChanged
        }

        guard let range = try managedRange(in: currentConfiguration) else { return }
        var updated = currentConfiguration
        updated.removeSubrange(range)
        updated = Self.normalizeAfterRemoval(updated)
        try write(updated, to: plan.configurationURL)
    }

    static func managedBlock(
        shell: SupportedShell,
        executableURL: URL,
        completionDirectoryURL: URL
    ) -> String {
        switch shell {
        case .bash:
            let executable = singleQuotedShellLiteral(executableURL.path)
            return """
            \(beginMarker)
            . <(\(executable) completion bash)
            \(endMarker)
            """
        case .zsh:
            let directory = singleQuotedShellLiteral(completionDirectoryURL.path)
            return """
            \(beginMarker)
            fpath=(\(directory) $fpath)
            autoload -Uz compinit && compinit
            \(endMarker)
            """
        }
    }

    private func managedRange(in contents: String) throws -> Range<String.Index>? {
        let begin = contents.range(of: Self.beginMarker)
        let end = contents.range(of: Self.endMarker)

        if (begin == nil) != (end == nil) {
            throw ShellCompletionError.malformedManagedBlock
        }
        guard let begin, let end, begin.lowerBound < end.lowerBound else {
            if begin == nil && end == nil { return nil }
            throw ShellCompletionError.malformedManagedBlock
        }
        return begin.lowerBound..<end.upperBound
    }

    private func readTextIfExists(_ url: URL) throws -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func write(_ contents: String, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let existed = fileManager.fileExists(atPath: url.path)
        let attributes = existed ? try? fileManager.attributesOfItem(atPath: url.path) : nil
        let permissions = attributes?[.posixPermissions]

        try Data(contents.utf8).write(to: url, options: .atomic)
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private func restoreCompletionFile(_ original: String?, at url: URL) {
        do {
            if let original {
                try write(original, to: url)
            } else if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            // Best-effort rollback. The shell configuration write did not succeed,
            // so an orphaned completion file is harmless and can be regenerated.
        }
    }

    private static func appending(block: String, to contents: String) -> String {
        guard !contents.isEmpty else { return block + "\n" }
        let separator = contents.hasSuffix("\n\n") ? "" : (contents.hasSuffix("\n") ? "\n" : "\n\n")
        return contents + separator + block + "\n"
    }

    private static func normalizeAfterRemoval(_ contents: String) -> String {
        var result = contents.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        while result.hasSuffix("\n\n\n") {
            result.removeLast()
        }
        return result
    }

    private static func singleQuotedShellLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

@MainActor
@Observable
final class ShellCompletionModel {
    var selectedShell: SupportedShell
    var plan: ShellCompletionPlan?
    var errorMessage: String?
    var isLoading = false
    var isApplying = false

    private let service: ShellCompletionService
    private let asdfService: AsdfService
    private var requestID = UUID()

    init(
        service: ShellCompletionService = ShellCompletionService(),
        asdfService: AsdfService = AsdfService(),
        detectedShellPath: String? = ProcessInfo.processInfo.environment["SHELL"]
    ) {
        self.service = service
        self.asdfService = asdfService
        self.selectedShell = SupportedShell.detect(from: detectedShellPath) ?? .zsh
    }

    func selectShell(_ shell: SupportedShell, executableURL: URL?) {
        selectedShell = shell
        Task { await refresh(executableURL: executableURL) }
    }

    func refresh(executableURL: URL?) async {
        let request = UUID()
        requestID = request
        guard let executableURL else {
            plan = nil
            errorMessage = "asdf executable is not available."
            return
        }

        let shell = selectedShell
        isLoading = true
        errorMessage = nil
        defer {
            if requestID == request { isLoading = false }
        }

        do {
            let completionScript: String?
            if shell == .zsh {
                completionScript = try await asdfService.completionScript(executable: executableURL, shell: .zsh)
            } else {
                completionScript = nil
            }
            guard requestID == request, selectedShell == shell else { return }
            plan = try service.plan(
                shell: shell,
                executableURL: executableURL,
                completionScript: completionScript
            )
        } catch is CancellationError {
            return
        } catch {
            guard requestID == request else { return }
            plan = nil
            errorMessage = error.localizedDescription
        }
    }

    func apply(appModel: AppModel) async {
        guard !isApplying, let plan, appModel.beginExternalWriteOperation() else { return }
        isApplying = true
        defer {
            isApplying = false
            appModel.endExternalWriteOperation()
        }

        do {
            try service.apply(plan)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh(executableURL: appModel.executableURL)
    }

    func remove(appModel: AppModel) async {
        guard !isApplying, let plan, appModel.beginExternalWriteOperation() else { return }
        isApplying = true
        defer {
            isApplying = false
            appModel.endExternalWriteOperation()
        }

        do {
            try service.remove(plan)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh(executableURL: appModel.executableURL)
    }
}
