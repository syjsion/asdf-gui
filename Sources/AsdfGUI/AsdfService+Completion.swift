import Foundation

extension AsdfService {
    func completionScript(executable: URL, shell: SupportedShell) async throws -> String {
        let result = try await AsdfCommandRunner().run(
            executable: executable,
            arguments: ["completion", shell.rawValue]
        )

        guard result.exitCode == 0 else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AsdfError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AsdfError.commandFailed("asdf completion returned no output for \(shell.rawValue).")
        }

        return result.stdout.hasSuffix("\n") ? result.stdout : result.stdout + "\n"
    }
}
