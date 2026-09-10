import Foundation

enum AsdfError: LocalizedError {
    case executableNotFound
    case invalidExecutable(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Could not find the asdf executable. Configure its path in Settings."
        case .invalidExecutable(let path):
            return "The selected asdf executable is not executable: \(path)"
        case .commandFailed(let message):
            return message.isEmpty ? "asdf command failed." : message
        }
    }
}

enum AsdfVersionSetScope: Hashable {
    case project(URL)
    case home
}

struct AsdfCurrentEntry: Identifiable, Hashable, Sendable {
    let name: String
    let version: String
    let source: String?
    let isInstalled: Bool

    var id: String { "\(name)|\(version)|\(source ?? "")" }
}

struct AsdfShimProvider: Identifiable, Hashable, Sendable {
    let plugin: String
    let version: String

    var id: String { "\(plugin)@\(version)" }
}

struct AsdfPluginCatalogEntry: Identifiable, Hashable, Sendable {
    let name: String
    let url: String?

    var id: String { name }
}

struct AsdfService {
    private let runner = AsdfCommandRunner()

    func locateExecutable(preferred: URL? = nil) throws -> URL {
        let fm = FileManager.default

        if let preferred {
            let standardized = preferred.standardizedFileURL
            guard fm.isExecutableFile(atPath: standardized.path) else {
                throw AsdfError.invalidExecutable(standardized.path)
            }
            return standardized
        }

        let home = fm.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/asdf"),
            URL(fileURLWithPath: "/usr/local/bin/asdf"),
            home.appendingPathComponent(".local/bin/asdf"),
            home.appendingPathComponent("go/bin/asdf")
        ]
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) {
            return found
        }
        throw AsdfError.executableNotFound
    }

    func version(executable: URL) async throws -> String {
        let result = try await runner.run(executable: executable, arguments: ["version"])
        return try checkedText(result)
    }

    func plugins(executable: URL) async throws -> [AsdfPlugin] {
        let result = try await runner.run(executable: executable, arguments: ["plugin", "list", "--urls"])
        guard result.exitCode == 0 else { throw commandError(result) }
        return Self.parsePlugins(result.stdout)
    }

    func pluginCatalog(executable: URL) async throws -> [AsdfPluginCatalogEntry] {
        let result = try await runner.run(executable: executable, arguments: ["plugin", "list", "all"])
        guard result.exitCode == 0 else { throw commandError(result) }
        return Self.parsePluginCatalog(result.stdout)
    }

    func current(
        executable: URL,
        tool: String? = nil,
        currentDirectory: URL? = nil
    ) async throws -> [AsdfCurrentEntry] {
        var arguments = ["current"]
        if let tool = normalizedOptional(tool) {
            arguments.append(tool)
        }
        let result = try await runner.run(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory
        )
        guard result.exitCode == 0 else { throw commandError(result) }
        return Self.parseCurrent(result.stdout)
    }

    func shimVersions(executable: URL, command: String) async throws -> [AsdfShimProvider] {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw AsdfError.commandFailed("A shim command is required.")
        }
        let result = try await runner.run(executable: executable, arguments: ["shimversions", command])
        guard result.exitCode == 0 else { throw commandError(result) }
        return Self.parseShimVersions(result.stdout)
    }

    func installedVersions(executable: URL, tool: String) async throws -> [String] {
        let result = try await runner.run(executable: executable, arguments: ["list", tool])
        guard result.exitCode == 0 else { throw commandError(result) }
        return Self.parseInstalledVersions(result.stdout)
    }

    func availableVersions(executable: URL, tool: String) async throws -> [String] {
        let result = try await runner.run(executable: executable, arguments: ["list", "all", tool])
        guard result.exitCode == 0 else { throw commandError(result) }
        return Self.parseVersionLines(result.stdout)
    }

    func latestVersion(executable: URL, tool: String) async throws -> String {
        let result = try await runner.run(executable: executable, arguments: ["latest", tool])
        let value = try checkedText(result)
        guard !value.isEmpty else { throw AsdfError.commandFailed("asdf latest returned no version for \(tool).") }
        return value
    }

    func setVersion(
        executable: URL,
        tool: String,
        versions: [String],
        scope: AsdfVersionSetScope
    ) async throws -> AsdfCommandResult {
        guard !versions.isEmpty else {
            throw AsdfError.commandFailed("At least one version is required for asdf set.")
        }

        var arguments = ["set"]
        var currentDirectory: URL?

        switch scope {
        case .project(let directory):
            currentDirectory = directory
        case .home:
            arguments.append("-u")
        }

        arguments.append(tool)
        arguments.append(contentsOf: versions)

        let result = try await runner.run(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory
        )
        return try checkedResult(result)
    }

    func installVersion(
        executable: URL,
        tool: String,
        version: String,
        currentDirectory: URL? = nil,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
    ) async throws -> AsdfCommandResult {
        let result = try await runner.run(
            executable: executable,
            arguments: ["install", tool, version],
            currentDirectory: currentDirectory,
            onOutput: onOutput
        )
        return try checkedResult(result)
    }

    func uninstallVersion(
        executable: URL,
        tool: String,
        version: String,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
    ) async throws -> AsdfCommandResult {
        let result = try await runner.run(
            executable: executable,
            arguments: ["uninstall", tool, version],
            onOutput: onOutput
        )
        return try checkedResult(result)
    }

    func addPlugin(
        executable: URL,
        name: String,
        gitURL: String? = nil,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
    ) async throws -> AsdfCommandResult {
        var arguments = ["plugin", "add", name]
        if let gitURL = normalizedOptional(gitURL) {
            arguments.append(gitURL)
        }
        let result = try await runner.run(executable: executable, arguments: arguments, onOutput: onOutput)
        return try checkedResult(result)
    }

    func updatePlugin(
        executable: URL,
        name: String,
        gitRef: String? = nil,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
    ) async throws -> AsdfCommandResult {
        var arguments = ["plugin", "update", name]
        if let gitRef = normalizedOptional(gitRef) {
            arguments.append(gitRef)
        }
        let result = try await runner.run(executable: executable, arguments: arguments, onOutput: onOutput)
        return try checkedResult(result)
    }

    func updateAllPlugins(
        executable: URL,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
    ) async throws -> AsdfCommandResult {
        let result = try await runner.run(
            executable: executable,
            arguments: ["plugin", "update", "--all"],
            onOutput: onOutput
        )
        return try checkedResult(result)
    }

    func removePlugin(
        executable: URL,
        name: String,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
    ) async throws -> AsdfCommandResult {
        let result = try await runner.run(
            executable: executable,
            arguments: ["plugin", "remove", name],
            onOutput: onOutput
        )
        return try checkedResult(result)
    }

    func info(executable: URL) async throws -> String {
        let result = try await runner.run(executable: executable, arguments: ["info"])
        return try checkedText(result)
    }

    func wherePath(executable: URL, tool: String, version: String? = nil) async throws -> String {
        var arguments = ["where", tool]
        if let version = normalizedOptional(version) {
            arguments.append(version)
        }
        let result = try await runner.run(executable: executable, arguments: arguments)
        return try checkedText(result)
    }

    func whichPath(executable: URL, command: String) async throws -> String {
        let result = try await runner.run(executable: executable, arguments: ["which", command])
        return try checkedText(result)
    }

    func reshim(executable: URL, tool: String, version: String) async throws -> AsdfCommandResult {
        let result = try await runner.run(executable: executable, arguments: ["reshim", tool, version])
        return try checkedResult(result)
    }

    static func parsePlugins(_ output: String) -> [AsdfPlugin] {
        output.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return AsdfPlugin(name: name, url: parts.count > 1 ? parts[1] : nil)
        }
    }

    static func parsePluginCatalog(_ output: String) -> [AsdfPluginCatalogEntry] {
        output.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return AsdfPluginCatalogEntry(name: name, url: parts.count > 1 ? parts[1] : nil)
        }
    }

    static func parseCurrent(_ output: String) -> [AsdfCurrentEntry] {
        output
            .split(whereSeparator: { $0.isNewline })
            .compactMap { rawLine in
                let columns = splitAlignedColumns(String(rawLine))
                guard !columns.isEmpty else { return nil }
                if columns[0].caseInsensitiveCompare("Name") == .orderedSame {
                    return nil
                }
                guard columns.count >= 3 else { return nil }

                let installedText = columns.last?.lowercased() ?? ""
                guard installedText == "true" || installedText == "false" else { return nil }

                let name = columns[0]
                let version = columns[1]
                let source = columns.count >= 4 ? columns[2] : nil
                return AsdfCurrentEntry(
                    name: name,
                    version: version,
                    source: source?.isEmpty == false ? source : nil,
                    isInstalled: installedText == "true"
                )
            }
    }

    static func parseShimVersions(_ output: String) -> [AsdfShimProvider] {
        output.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return AsdfShimProvider(plugin: parts[0], version: parts[1])
        }
    }

    static func parseInstalledVersions(_ output: String) -> [String] {
        parseVersionLines(output).map { value in
            guard value.hasPrefix("*") else { return value }
            return value.dropFirst().trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    static func parseVersionLines(_ output: String) -> [String] {
        output
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func splitAlignedColumns(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var whitespaceRun = ""

        func flushWhitespace() {
            guard !whitespaceRun.isEmpty else { return }
            if whitespaceRun.contains("\t") || whitespaceRun.count >= 2 {
                let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { columns.append(value) }
                current = ""
            } else {
                current.append(" ")
            }
            whitespaceRun = ""
        }

        for character in line {
            if character == " " || character == "\t" {
                whitespaceRun.append(character)
            } else {
                flushWhitespace()
                current.append(character)
            }
        }
        flushWhitespace()

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { columns.append(tail) }
        return columns
    }

    private func checkedResult(_ result: AsdfCommandResult) throws -> AsdfCommandResult {
        guard result.exitCode == 0 else { throw commandError(result) }
        return result
    }

    private func checkedText(_ result: AsdfCommandResult) throws -> String {
        let checked = try checkedResult(result)
        return checked.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commandError(_ result: AsdfCommandResult) -> AsdfError {
        let message = result.stderr.isEmpty ? result.stdout : result.stderr
        return .commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
