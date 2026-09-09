import XCTest
@testable import AsdfGUI

final class PluginManagementTests: XCTestCase {
    func testRemovalInspectorFindsProjectsReferencingPlugin() {
        let nodeProject = ManagedProject(path: "/tmp/node-app")
        let pythonProject = ManagedProject(path: "/tmp/python-app")
        let snapshots = [
            ProjectSnapshot(
                project: nodeProject,
                hasToolVersionsFile: true,
                requirements: [ToolRequirement(tool: "nodejs", versions: ["22.18.0"])],
                errorMessage: nil
            ),
            ProjectSnapshot(
                project: pythonProject,
                hasToolVersionsFile: true,
                requirements: [ToolRequirement(tool: "python", versions: ["3.13.2"])],
                errorMessage: nil
            )
        ]

        XCTAssertEqual(
            PluginRemovalInspector.projectsReferencing(pluginName: "nodejs", snapshots: snapshots),
            [nodeProject]
        )
    }

    func testPluginCommandsUseExpectedArguments() async throws {
        let fixture = try makeCaptureExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = AsdfService()

        _ = try await service.addPlugin(
            executable: fixture.executable,
            name: "nodejs",
            gitURL: "https://github.com/asdf-vm/asdf-nodejs.git",
            onOutput: { _ in }
        )
        XCTAssertEqual(try capturedArguments(fixture.arguments), [
            "plugin", "add", "nodejs", "https://github.com/asdf-vm/asdf-nodejs.git"
        ])

        _ = try await service.updatePlugin(
            executable: fixture.executable,
            name: "nodejs",
            gitRef: "main",
            onOutput: { _ in }
        )
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["plugin", "update", "nodejs", "main"])

        _ = try await service.updateAllPlugins(executable: fixture.executable, onOutput: { _ in })
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["plugin", "update", "--all"])

        _ = try await service.removePlugin(executable: fixture.executable, name: "nodejs", onOutput: { _ in })
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["plugin", "remove", "nodejs"])
    }

    func testPluginAddWithoutURLUsesShortNameForm() async throws {
        let fixture = try makeCaptureExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        _ = try await AsdfService().addPlugin(
            executable: fixture.executable,
            name: "erlang",
            gitURL: nil,
            onOutput: { _ in }
        )

        XCTAssertEqual(try capturedArguments(fixture.arguments), ["plugin", "add", "erlang"])
    }

    private func capturedArguments(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
    }

    private func makeCaptureExecutable() throws -> (root: URL, executable: URL, arguments: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-asdf")
        let arguments = root.appendingPathComponent("arguments.txt")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(arguments.path)'
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, executable, arguments)
    }
}
