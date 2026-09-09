import Foundation

enum AsdfError: LocalizedError {
    case executableNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Could not find the asdf executable. Configure its path in Settings."
        case .commandFailed(let message):
            return message.isEmpty ? "asdf command failed." : message
        }
    }
}

struct AsdfCommandRunner {
    func run(executable: URL, arguments: [String], currentDirectory: URL? = nil) async throws -> AsdfCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: AsdfCommandResult(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

struct AsdfService {
    private let runner = AsdfCommandRunner()

    func locateExecutable() throws -> URL {
        let fm = FileManager.default
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

    static func parsePlugins(_ output: String) -> [AsdfPlugin] {
        output.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let name = parts.first, !name.isEmpty else { return nil }
            return AsdfPlugin(name: name, url: parts.count > 1 ? parts[1] : nil)
        }
    }
}
