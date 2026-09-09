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
        guard result.exitCode == 0 else { throw AsdfError.commandFailed(result.stderr) }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func plugins(executable: URL) async throws -> [AsdfPlugin] {
        let result = try await runner.run(executable: executable, arguments: ["plugin", "list", "--urls"])
        guard result.exitCode == 0 else { throw AsdfError.commandFailed(result.stderr) }
        return Self.parsePlugins(result.stdout)
    }

    func installedVersions(executable: URL, tool: String) async throws -> [String] {
        let result = try await runner.run(executable: executable, arguments: ["list", tool])
        guard result.exitCode == 0 else { throw AsdfError.commandFailed(result.stderr) }
        return Self.parseInstalledVersions(result.stdout)
    }

    func installVersion(
        executable: URL,
        tool: String,
        version: String,
        currentDirectory: URL,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
    ) async throws -> AsdfCommandResult {
        let result = try await runner.run(
            executable: executable,
            arguments: ["install", tool, version],
            currentDirectory: currentDirectory,
            onOutput: onOutput
        )

        guard result.exitCode == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AsdfError.commandFailed(message)
        }
        return result
    }

    static func parsePlugins(_ output: String) -> [AsdfPlugin] {
        output.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return AsdfPlugin(name: name, url: parts.count > 1 ? parts[1] : nil)
        }
    }

    static func parseInstalledVersions(_ output: String) -> [String] {
        output.split(whereSeparator: { $0.isNewline }).compactMap { line in
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("*") {
                value.removeFirst()
                value = value.trimmingCharacters(in: .whitespaces)
            }
            return value.isEmpty ? nil : value
        }
    }
}
