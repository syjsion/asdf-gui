import XCTest
@testable import AsdfGUI

final class VersionSelectionTests: XCTestCase {
    func testSetProjectVersionUsesProjectWorkingDirectory() async throws {
        let fixture = try makeCaptureExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let project = fixture.root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        _ = try await AsdfService().setVersion(
            executable: fixture.executable,
            tool: "nodejs",
            versions: ["22.18.0"],
            scope: .project(project)
        )

        let arguments = try String(contentsOf: fixture.arguments, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
        let workingDirectory = try String(contentsOf: fixture.workingDirectory, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedWorkingDirectory = URL(fileURLWithPath: workingDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let resolvedProject = project
            .resolvingSymlinksInPath()
            .standardizedFileURL

        XCTAssertEqual(arguments, ["set", "nodejs", "22.18.0"])
        XCTAssertEqual(resolvedWorkingDirectory.path, resolvedProject.path)
    }

    func testSetProjectVersionPreservesFallbackArgumentOrder() async throws {
        let fixture = try makeCaptureExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let project = fixture.root.appendingPathComponent("fallback-project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        _ = try await AsdfService().setVersion(
            executable: fixture.executable,
            tool: "python",
            versions: ["3.13.2", "3.12.9", "system"],
            scope: .project(project)
        )

        let arguments = try String(contentsOf: fixture.arguments, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)

        XCTAssertEqual(arguments, ["set", "python", "3.13.2", "3.12.9", "system"])
    }

    func testSetHomeVersionUsesHomeFlagAndSupportsFallbackArguments() async throws {
        let fixture = try makeCaptureExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        _ = try await AsdfService().setVersion(
            executable: fixture.executable,
            tool: "python",
            versions: ["3.13.2", "system"],
            scope: .home
        )

        let arguments = try String(contentsOf: fixture.arguments, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)

        XCTAssertEqual(arguments, ["set", "-u", "python", "3.13.2", "system"])
    }

    func testSetVersionRejectsEmptyVersionList() async throws {
        let fixture = try makeCaptureExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        do {
            _ = try await AsdfService().setVersion(
                executable: fixture.executable,
                tool: "nodejs",
                versions: [],
                scope: .home
            )
            XCTFail("Expected empty version list to fail")
        } catch let error as AsdfError {
            XCTAssertEqual(error.localizedDescription, "At least one version is required for asdf set.")
        }
    }

    private func makeCaptureExecutable() throws -> (
        root: URL,
        executable: URL,
        arguments: URL,
        workingDirectory: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let executable = root.appendingPathComponent("fake-asdf")
        let arguments = root.appendingPathComponent("arguments.txt")
        let workingDirectory = root.appendingPathComponent("pwd.txt")

        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(arguments.path)'
        pwd > '\(workingDirectory.path)'
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        return (root, executable, arguments, workingDirectory)
    }
}
