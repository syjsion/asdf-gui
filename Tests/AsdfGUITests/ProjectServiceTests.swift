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
