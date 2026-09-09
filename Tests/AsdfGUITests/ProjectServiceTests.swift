import XCTest
@testable import AsdfGUI

final class ProjectServiceTests: XCTestCase {
    func testParseToolVersionsPreservesFallbackOrderAndComments() {
        let contents = """
        # project runtimes
        nodejs 22.18.0
        python 3.13.2 3.12.9 system # fallback chain

        ruby 3.4.1
        invalid-line
        """

        let requirements = ToolVersionsParser.parse(contents)

        XCTAssertEqual(requirements, [
            ToolRequirement(tool: "nodejs", versions: ["22.18.0"]),
            ToolRequirement(tool: "python", versions: ["3.13.2", "3.12.9", "system"]),
            ToolRequirement(tool: "ruby", versions: ["3.4.1"])
        ])
    }

    func testRequirementStatusResolver() {
        let installed: Set<String> = ["22.18.0"]

        XCTAssertEqual(
            RequirementStatusResolver.resolve(
                version: "22.18.0",
                installedVersions: installed,
                pluginInstalled: true,
                lookupFailed: false
            ),
            .installed
        )
        XCTAssertEqual(
            RequirementStatusResolver.resolve(
                version: "20.19.4",
                installedVersions: installed,
                pluginInstalled: true,
                lookupFailed: false
            ),
            .missing
        )
        XCTAssertEqual(
            RequirementStatusResolver.resolve(
                version: "system",
                installedVersions: installed,
                pluginInstalled: true,
                lookupFailed: false
            ),
            .system
        )
        XCTAssertEqual(
            RequirementStatusResolver.resolve(
                version: "path:~/src/node",
                installedVersions: installed,
                pluginInstalled: true,
                lookupFailed: false
            ),
            .path
        )
        XCTAssertEqual(
            RequirementStatusResolver.resolve(
                version: "22.18.0",
                installedVersions: installed,
                pluginInstalled: false,
                lookupFailed: false
            ),
            .pluginMissing
        )
        XCTAssertEqual(
            RequirementStatusResolver.resolve(
                version: "22.18.0",
                installedVersions: nil,
                pluginInstalled: true,
                lookupFailed: true
            ),
            .unknown
        )
    }

    func testProjectInstallPlannerUsesFirstMissingFallbackOnlyWhenUnsatisfied() {
        let requirements = [
            ToolRequirement(tool: "nodejs", versions: ["22.18.0", "20.19.4"]),
            ToolRequirement(tool: "python", versions: ["3.13.2", "3.12.9"]),
            ToolRequirement(tool: "ruby", versions: ["3.4.1"]),
            ToolRequirement(tool: "elixir", versions: ["1.18.4"])
        ]

        let statuses: [String: RequirementVersionStatus] = [
            "nodejs@22.18.0": .missing,
            "nodejs@20.19.4": .missing,
            "python@3.13.2": .missing,
            "python@3.12.9": .installed,
            "ruby@3.4.1": .pluginMissing,
            "elixir@1.18.4": .unknown
        ]

        let plan = ProjectInstallPlanner.plan(requirements: requirements) { tool, version in
            statuses["\(tool)@\(version)"] ?? .unknown
        }

        XCTAssertEqual(plan, [ProjectInstallItem(tool: "nodejs", version: "22.18.0")])
    }

    func testProjectInstallPlannerPlansEachToolAtMostOnce() {
        let requirements = [
            ToolRequirement(tool: "nodejs", versions: ["22.18.0"]),
            ToolRequirement(tool: "nodejs", versions: ["20.19.4"])
        ]

        let plan = ProjectInstallPlanner.plan(requirements: requirements) { _, _ in .missing }

        XCTAssertEqual(plan, [ProjectInstallItem(tool: "nodejs", version: "22.18.0")])
    }

    func testSnapshotReadsToolVersionsFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try "nodejs 22.18.0\npython 3.13.2\n".write(
            to: directory.appendingPathComponent(".tool-versions"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = ProjectService().snapshot(for: ManagedProject(path: directory.path))

        XCTAssertTrue(snapshot.hasToolVersionsFile)
        XCTAssertNil(snapshot.errorMessage)
        XCTAssertEqual(snapshot.requirements.count, 2)
        XCTAssertEqual(snapshot.requirements.first?.tool, "nodejs")
    }

    func testSnapshotHandlesMissingToolVersionsFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let snapshot = ProjectService().snapshot(for: ManagedProject(path: directory.path))

        XCTAssertFalse(snapshot.hasToolVersionsFile)
        XCTAssertTrue(snapshot.requirements.isEmpty)
        XCTAssertNil(snapshot.errorMessage)
    }
}
