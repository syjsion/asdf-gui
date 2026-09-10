import XCTest
@testable import AsdfGUI

final class ResolutionTests: XCTestCase {
    func testParseCurrentFourColumnOutputPreservesFallbacksAndSourceSpaces() {
        let output = """
        Name            Version              Source                                      Installed
        nodejs          22.18.0 20.19.0      /Users/Test User/work/.tool-versions        true
        python          3.13.2               /Users/Test User/.tool-versions             false
        """

        let entries = AsdfService.parseCurrent(output)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "nodejs")
        XCTAssertEqual(entries[0].version, "22.18.0 20.19.0")
        XCTAssertEqual(entries[0].source, "/Users/Test User/work/.tool-versions")
        XCTAssertTrue(entries[0].isInstalled)
        XCTAssertEqual(entries[1].name, "python")
        XCTAssertFalse(entries[1].isInstalled)
    }

    func testParseCurrentAllowsMissingSourceColumn() {
        let output = """
        Name            Version         Source      Installed
        nodejs          system                      true
        """

        let entries = AsdfService.parseCurrent(output)
        XCTAssertEqual(entries, [AsdfCurrentEntry(name: "nodejs", version: "system", source: nil, isInstalled: true)])
    }

    func testParseShimVersions() {
        let providers = AsdfService.parseShimVersions("nodejs 20.19.0\nnodejs 22.18.0\n")
        XCTAssertEqual(providers, [
            AsdfShimProvider(plugin: "nodejs", version: "20.19.0"),
            AsdfShimProvider(plugin: "nodejs", version: "22.18.0")
        ])
    }

    func testParsePluginCatalog() {
        let catalog = AsdfService.parsePluginCatalog("nodejs https://github.com/asdf-vm/asdf-nodejs.git\npython https://github.com/danhper/asdf-python.git\n")
        XCTAssertEqual(catalog, [
            AsdfPluginCatalogEntry(name: "nodejs", url: "https://github.com/asdf-vm/asdf-nodejs.git"),
            AsdfPluginCatalogEntry(name: "python", url: "https://github.com/danhper/asdf-python.git")
        ])
    }

    func testCurrentUsesSelectedProjectDirectory() async throws {
        let fixture = try makeCaptureExecutable(stdout: "Name  Version  Source  Installed\nnodejs  22.18.0  /tmp/.tool-versions  true\n")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let project = fixture.root.appendingPathComponent("Project Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        _ = try await AsdfService().current(
            executable: fixture.executable,
            tool: "nodejs",
            currentDirectory: project
        )

        XCTAssertEqual(try capturedArguments(fixture.arguments), ["current", "nodejs"])
        XCTAssertEqual(
            try capturedDirectory(fixture.workingDirectory),
            project.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func testShimVersionsUsesExpectedCommand() async throws {
        let fixture = try makeCaptureExecutable(stdout: "nodejs 22.18.0\n")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        _ = try await AsdfService().shimVersions(executable: fixture.executable, command: "node")
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["shimversions", "node"])
    }

    func testPluginCatalogUsesListAllCommand() async throws {
        let fixture = try makeCaptureExecutable(stdout: "nodejs https://example.com/node.git\n")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        _ = try await AsdfService().pluginCatalog(executable: fixture.executable)
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["plugin", "list", "all"])
    }

    func testWhichPathUsesSelectedDirectory() async throws {
        let fixture = try makeCaptureExecutable(stdout: "/tmp/node\n")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let project = fixture.root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let path = try await AsdfService().whichPathInDirectory(
            executable: fixture.executable,
            command: "node",
            currentDirectory: project
        )

        XCTAssertEqual(path, "/tmp/node")
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["which", "node"])
        XCTAssertEqual(
            try capturedDirectory(fixture.workingDirectory),
            project.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    private func makeCaptureExecutable(stdout: String) throws -> (
        root: URL,
        executable: URL,
        arguments: URL,
        workingDirectory: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-asdf")
        let arguments = root.appendingPathComponent("args.txt")
        let workingDirectory = root.appendingPathComponent("pwd.txt")
        let escapedOutput = stdout.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(arguments.path)'
        pwd > '\(workingDirectory.path)'
        printf '%s' '\(escapedOutput)'
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, executable, arguments, workingDirectory)
    }

    private func capturedArguments(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
    }

    private func capturedDirectory(_ url: URL) throws -> String {
        let path = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
