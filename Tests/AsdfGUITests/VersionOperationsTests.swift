import XCTest
@testable import AsdfGUI

final class VersionOperationsTests: XCTestCase {
    func testUsageInspectorFindsProjectsReferencingExactToolAndVersion() {
        let api = ManagedProject(path: "/tmp/api")
        let web = ManagedProject(path: "/tmp/web")
        let ruby = ManagedProject(path: "/tmp/ruby")

        let snapshots = [
            ProjectSnapshot(
                project: api,
                hasToolVersionsFile: true,
                requirements: [ToolRequirement(tool: "nodejs", versions: ["22.19.0", "20.19.5"])],
                errorMessage: nil
            ),
            ProjectSnapshot(
                project: web,
                hasToolVersionsFile: true,
                requirements: [ToolRequirement(tool: "nodejs", versions: ["24.7.0"])],
                errorMessage: nil
            ),
            ProjectSnapshot(
                project: ruby,
                hasToolVersionsFile: true,
                requirements: [ToolRequirement(tool: "ruby", versions: ["22.19.0"])],
                errorMessage: nil
            )
        ]

        XCTAssertEqual(
            VersionUsageInspector.projectsUsing(
                tool: "nodejs",
                version: "22.19.0",
                snapshots: snapshots
            ),
            [api]
        )
    }

    func testUsageInspectorTreatsFallbackReferenceAsUsage() {
        let project = ManagedProject(path: "/tmp/fallback")
        let snapshot = ProjectSnapshot(
            project: project,
            hasToolVersionsFile: true,
            requirements: [ToolRequirement(tool: "python", versions: ["3.13.2", "3.12.9", "system"])],
            errorMessage: nil
        )

        XCTAssertEqual(
            VersionUsageInspector.projectsUsing(
                tool: "python",
                version: "3.12.9",
                snapshots: [snapshot]
            ),
            [project]
        )
    }

    func testUsageInspectorRequiresExactVersionMatch() {
        let project = ManagedProject(path: "/tmp/exact")
        let snapshot = ProjectSnapshot(
            project: project,
            hasToolVersionsFile: true,
            requirements: [ToolRequirement(tool: "nodejs", versions: ["22.19.0"])],
            errorMessage: nil
        )

        XCTAssertTrue(
            VersionUsageInspector.projectsUsing(
                tool: "nodejs",
                version: "22.19",
                snapshots: [snapshot]
            ).isEmpty
        )
    }
}
