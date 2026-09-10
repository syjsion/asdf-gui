import XCTest
@testable import AsdfGUI

final class AdvancedManagementTests: XCTestCase {
    func testParseEnvironmentPreservesEqualsInValuesAndSortsKeys() {
        let entries = AsdfService.parseEnvironment("""
        PATH=/one:/two
        TOKEN=a=b=c
        ASDF_NODEJS_VERSION=22.18.0
        malformed-line
        """)

        XCTAssertEqual(entries.map(\.key), ["ASDF_NODEJS_VERSION", "PATH", "TOKEN"])
        XCTAssertEqual(entries.first(where: { $0.key == "TOKEN" })?.value, "a=b=c")
    }

    func testEnvironmentComparisonDetectsChangedAddedAndRemovedVariables() {
        let home = [
            AsdfEnvironmentEntry(key: "PATH", value: "/home/bin"),
            AsdfEnvironmentEntry(key: "HOME_ONLY", value: "1")
        ]
        let project = [
            AsdfEnvironmentEntry(key: "PATH", value: "/project/bin:/home/bin"),
            AsdfEnvironmentEntry(key: "PROJECT_ONLY", value: "yes")
        ]

        let rows = EnvironmentComparison.rows(home: home, context: project)
        XCTAssertEqual(rows.map(\.key), ["HOME_ONLY", "PATH", "PROJECT_ONLY"])
        XCTAssertTrue(rows.allSatisfy(\.isChanged))
        XCTAssertNil(rows.first(where: { $0.key == "HOME_ONLY" })?.contextValue)
        XCTAssertNil(rows.first(where: { $0.key == "PROJECT_ONLY" })?.homeValue)
    }

    func testParentLocatorFindsClosestAncestorConfiguration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let nested = workspace.appendingPathComponent("apps/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let rootConfig = root.appendingPathComponent(".tool-versions")
        let workspaceConfig = workspace.appendingPathComponent(".tool-versions")
        try "nodejs 20.0.0\n".write(to: rootConfig, atomically: true, encoding: .utf8)
        try "nodejs 22.0.0\n".write(to: workspaceConfig, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            ParentToolVersionsLocator.nearestParentFile(from: nested)?.standardizedFileURL.path,
            workspaceConfig.standardizedFileURL.path
        )
    }

    func testSetParentVersionUsesParentFlagAndProjectWorkingDirectory() async throws {
        let fixture = try makeCaptureExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let project = fixture.root.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        _ = try await AsdfService().setVersion(
            executable: fixture.executable,
            tool: "nodejs",
            versions: ["22.18.0"],
            scope: .parent(project)
        )

        let arguments = try String(contentsOf: fixture.arguments, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
        let workingDirectory = try String(contentsOf: fixture.workingDirectory, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(arguments, ["set", "-p", "nodejs", "22.18.0"])
        XCTAssertEqual(
            URL(fileURLWithPath: workingDirectory).resolvingSymlinksInPath().standardizedFileURL.path,
            project.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func testRuntimeUpdateRecordRequiresExactLatestVersionToBeInstalled() {
        let current = RuntimeUpdateRecord(
            tool: "nodejs",
            installedVersions: ["22.18.0", "24.1.0"],
            latestVersion: "24.1.0",
            errorMessage: nil
        )
        XCTAssertTrue(current.latestInstalled)
        XCTAssertFalse(current.canInstallLatest)

        let update = RuntimeUpdateRecord(
            tool: "nodejs",
            installedVersions: ["22.18.0"],
            latestVersion: "24.1.0",
            errorMessage: nil
        )
        XCTAssertFalse(update.latestInstalled)
        XCTAssertTrue(update.canInstallLatest)
    }

    func testProjectHealthTreatsSatisfiedFallbackAsHealthy() {
        let snapshot = ProjectSnapshot(
            project: ManagedProject(path: "/tmp/demo"),
            hasToolVersionsFile: true,
            requirements: [ToolRequirement(tool: "nodejs", versions: ["24.0.0", "22.18.0"])],
            errorMessage: nil
        )
        let issues = ProjectHealthAnalyzer.issues(snapshot: snapshot) { _, version in
            version == "22.18.0" ? .installed : .missing
        }
        XCTAssertTrue(issues.isEmpty)
    }

    func testProjectHealthPrioritizesPluginMissingAndRuntimeMissing() {
        let snapshot = ProjectSnapshot(
            project: ManagedProject(path: "/tmp/demo"),
            hasToolVersionsFile: true,
            requirements: [
                ToolRequirement(tool: "nodejs", versions: ["24.0.0"]),
                ToolRequirement(tool: "python", versions: ["3.13.0"])
            ],
            errorMessage: nil
        )
        let issues = ProjectHealthAnalyzer.issues(snapshot: snapshot) { tool, _ in
            tool == "nodejs" ? .pluginMissing : .missing
        }

        XCTAssertEqual(issues.count, 2)
        XCTAssertTrue(issues.contains { $0.id == "plugin-missing-nodejs" && $0.severity == .error })
        XCTAssertTrue(issues.contains { $0.id == "runtime-missing-python" && $0.severity == .error })
    }

    private func makeCaptureExecutable() throws -> (
        root: URL,
        executable: URL,
        arguments: URL,
        workingDirectory: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, executable, arguments, workingDirectory)
    }
}
