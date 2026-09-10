import XCTest
@testable import AsdfGUI

final class ProjectToolVersionsManagementTests: XCTestCase {
    func testRemovingToolPreservesOtherEntriesBlankLinesAndComments() throws {
        let contents = """
        # Runtime policy for this project
        nodejs 22.19.0 20.19.5 # Node fallback

        python 3.13.2 system
        ruby 3.4.5
        """ + "\n"

        let updated = try ToolVersionsMutationService.removingTool(
            from: contents,
            tool: "nodejs",
            expectedVersions: ["22.19.0", "20.19.5"]
        )

        XCTAssertEqual(
            updated,
            """
            # Runtime policy for this project

            python 3.13.2 system
            ruby 3.4.5
            """ + "\n"
        )
    }

    func testRemovingToolRejectsEntryChangedSinceViewLoaded() throws {
        let contents = "nodejs 24.8.0\npython 3.13.2\n"

        XCTAssertThrowsError(
            try ToolVersionsMutationService.removingTool(
                from: contents,
                tool: "nodejs",
                expectedVersions: ["22.19.0"]
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "The nodejs entry changed after this view was loaded. Refresh the project before removing it."
            )
        }
    }

    func testRemovingToolRejectsDuplicateToolEntries() throws {
        let contents = "nodejs 22.19.0\npython 3.13.2\nnodejs 20.19.5\n"

        XCTAssertThrowsError(
            try ToolVersionsMutationService.removingTool(
                from: contents,
                tool: "nodejs",
                expectedVersions: ["22.19.0"]
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                ".tool-versions contains more than one nodejs entry. Resolve the duplicate entries before removing this tool from asdf GUI."
            )
        }
    }

    func testRemovingLastLineWithoutTrailingNewline() throws {
        let contents = "python 3.13.2\nnodejs 22.19.0"

        let updated = try ToolVersionsMutationService.removingTool(
            from: contents,
            tool: "nodejs",
            expectedVersions: ["22.19.0"]
        )

        XCTAssertEqual(updated, "python 3.13.2\n")
    }

    func testFileRemovalPreservesPermissionsAndUnrelatedContent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let file = root.appendingPathComponent(".tool-versions")
        try "# keep me\nnodejs 22.19.0\npython 3.13.2\n".write(
            to: file,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)

        try ToolVersionsMutationService().removeTool(
            project: ManagedProject(path: root.path),
            tool: "nodejs",
            expectedVersions: ["22.19.0"]
        )

        let updated = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(updated, "# keep me\npython 3.13.2\n")

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o640)
    }

    func testValidationRejectsWhitespaceInToolAndVersions() throws {
        XCTAssertThrowsError(try ToolVersionsMutationService.validateTool("node js"))
        XCTAssertThrowsError(try ToolVersionsMutationService.validateVersions(["22.19.0", "bad value"]))

        XCTAssertEqual(
            try ToolVersionsMutationService.validateVersions(["22.19.0", "system", "ref:main"]),
            ["22.19.0", "system", "ref:main"]
        )
    }
}
