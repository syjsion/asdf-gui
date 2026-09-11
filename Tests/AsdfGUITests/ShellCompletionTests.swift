import XCTest
@testable import AsdfGUI

final class ShellCompletionTests: XCTestCase {
    func testCompletionCommandUsesTypedShellArgument() async throws {
        let fixture = try makeCaptureExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let output = try await AsdfService().completionScript(
            executable: fixture.executable,
            shell: .zsh
        )

        XCTAssertEqual(try capturedArguments(fixture.arguments), ["completion", "zsh"])
        XCTAssertEqual(output, "# completion fixture\n")
    }

    func testBashPlanUsesAbsoluteAsdfExecutableAndNoGeneratedFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("bin with space/asdf")
        let service = ShellCompletionService(homeDirectory: home, environment: [:])

        let plan = try service.plan(shell: .bash, executableURL: executable, completionScript: nil)

        XCTAssertEqual(plan.configurationURL, home.appendingPathComponent(".bash_profile"))
        XCTAssertNil(plan.completionFileURL)
        XCTAssertTrue(plan.managedBlock.contains(". <('\(executable.path)' completion bash)"))
        XCTAssertEqual(plan.status, .notConfigured)
    }

    func testZshApplyWritesManagedBlockAndGeneratedCompletion() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let data = root.appendingPathComponent("asdf-data", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let service = ShellCompletionService(
            homeDirectory: home,
            environment: ["ASDF_DATA_DIR": data.path]
        )
        let executable = root.appendingPathComponent("asdf")
        let script = "#compdef asdf\n_arguments '*: :->args'\n"

        let plan = try service.plan(shell: .zsh, executableURL: executable, completionScript: script)
        XCTAssertEqual(plan.completionFileURL, data.appendingPathComponent("completions/_asdf"))
        XCTAssertEqual(plan.status, .notConfigured)

        try service.apply(plan)

        let config = try String(contentsOf: home.appendingPathComponent(".zshrc"), encoding: .utf8)
        XCTAssertTrue(config.contains(ShellCompletionService.beginMarker))
        XCTAssertTrue(config.contains("fpath=('\(data.appendingPathComponent("completions").path)' $fpath)"))
        XCTAssertTrue(config.contains("autoload -Uz compinit && compinit"))
        XCTAssertEqual(
            try String(contentsOf: data.appendingPathComponent("completions/_asdf"), encoding: .utf8),
            script
        )

        let refreshed = try service.plan(shell: .zsh, executableURL: executable, completionScript: script)
        XCTAssertEqual(refreshed.status, .configured)
    }

    func testZshChangedGeneratedScriptReportsUpdateAvailable() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let service = ShellCompletionService(homeDirectory: home, environment: [:])
        let executable = root.appendingPathComponent("asdf")

        let first = try service.plan(shell: .zsh, executableURL: executable, completionScript: "old\n")
        try service.apply(first)
        let updated = try service.plan(shell: .zsh, executableURL: executable, completionScript: "new\n")

        XCTAssertEqual(updated.status, .needsUpdate)
    }

    func testApplyRejectsShellConfigurationChangedAfterPreview() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let service = ShellCompletionService(homeDirectory: home, environment: [:])
        let executable = root.appendingPathComponent("asdf")
        let plan = try service.plan(shell: .bash, executableURL: executable, completionScript: nil)

        try "user edit\n".write(to: plan.configurationURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try service.apply(plan)) { error in
            XCTAssertEqual(error as? ShellCompletionError, .configurationChanged)
        }
    }

    func testApplyRejectsGeneratedFileChangedAfterPreview() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let service = ShellCompletionService(homeDirectory: home, environment: [:])
        let executable = root.appendingPathComponent("asdf")
        let initial = try service.plan(shell: .zsh, executableURL: executable, completionScript: "old\n")
        try service.apply(initial)

        let updatePlan = try service.plan(shell: .zsh, executableURL: executable, completionScript: "new\n")
        let completionURL = try XCTUnwrap(updatePlan.completionFileURL)
        try "external edit\n".write(to: completionURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try service.apply(updatePlan)) { error in
            XCTAssertEqual(error as? ShellCompletionError, .completionFileChanged)
        }
    }

    func testRemoveDeletesOnlyManagedBlockAndRetainsGeneratedFile() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let zshrc = home.appendingPathComponent(".zshrc")
        try "export USER_SETTING=1\n".write(to: zshrc, atomically: true, encoding: .utf8)
        let service = ShellCompletionService(homeDirectory: home, environment: [:])
        let executable = root.appendingPathComponent("asdf")
        let script = "completion\n"

        let first = try service.plan(shell: .zsh, executableURL: executable, completionScript: script)
        try service.apply(first)
        let configured = try service.plan(shell: .zsh, executableURL: executable, completionScript: script)
        let completionURL = try XCTUnwrap(configured.completionFileURL)

        try service.remove(configured)

        let contents = try String(contentsOf: zshrc, encoding: .utf8)
        XCTAssertTrue(contents.contains("export USER_SETTING=1"))
        XCTAssertFalse(contents.contains(ShellCompletionService.beginMarker))
        XCTAssertTrue(FileManager.default.fileExists(atPath: completionURL.path))
    }

    func testRelativeASDFDataDirFallsBackToHomeDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let service = ShellCompletionService(
            homeDirectory: home,
            environment: ["ASDF_DATA_DIR": "relative/path"]
        )

        XCTAssertEqual(
            service.completionDirectoryURL().standardizedFileURL,
            home.appendingPathComponent(".asdf/completions", isDirectory: true).standardizedFileURL
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func capturedArguments(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
    }

    private func makeCaptureExecutable() throws -> (root: URL, executable: URL, arguments: URL) {
        let root = try makeTemporaryDirectory()
        let executable = root.appendingPathComponent("fake-asdf")
        let arguments = root.appendingPathComponent("arguments.txt")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(arguments.path)'
        printf '# completion fixture\\n'
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, executable, arguments)
    }
}
