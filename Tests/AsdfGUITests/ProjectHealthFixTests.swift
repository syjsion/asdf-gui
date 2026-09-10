import XCTest
@testable import AsdfGUI

final class ProjectHealthFixTests: XCTestCase {
    func testMissingPluginSuggestsPluginInstall() {
        let snapshot = ProjectSnapshot(
            project: ManagedProject(path: "/tmp/app"),
            hasToolVersionsFile: true,
            requirements: [ToolRequirement(tool: "nodejs", versions: ["22.20.0"])],
            errorMessage: nil
        )

        let issues = ProjectHealthAnalyzer.issues(snapshot: snapshot) { _, _ in .pluginMissing }

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.fix, .installPlugin(tool: "nodejs"))
    }

    func testMissingRuntimeSuggestsFirstMissingFallbackOnly() {
        let snapshot = ProjectSnapshot(
            project: ManagedProject(path: "/tmp/app"),
            hasToolVersionsFile: true,
            requirements: [ToolRequirement(tool: "python", versions: ["3.13.7", "3.12.11", "system"])],
            errorMessage: nil
        )

        let issues = ProjectHealthAnalyzer.issues(snapshot: snapshot) { _, version in
            switch version {
            case "3.13.7", "3.12.11": return .missing
            default: return .missing
            }
        }

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.fix, .installRuntime(tool: "python", version: "3.13.7"))
    }

    func testSatisfiedFallbackDoesNotOfferRepair() {
        let snapshot = ProjectSnapshot(
            project: ManagedProject(path: "/tmp/app"),
            hasToolVersionsFile: true,
            requirements: [ToolRequirement(tool: "python", versions: ["3.13.7", "3.12.11"])],
            errorMessage: nil
        )

        let issues = ProjectHealthAnalyzer.issues(snapshot: snapshot) { _, version in
            version == "3.12.11" ? .installed : .missing
        }

        XCTAssertTrue(issues.isEmpty)
    }

    func testUnknownRuntimeStatusDoesNotOfferUnsafeRepair() {
        let snapshot = ProjectSnapshot(
            project: ManagedProject(path: "/tmp/app"),
            hasToolVersionsFile: true,
            requirements: [ToolRequirement(tool: "ruby", versions: ["3.4.5"])],
            errorMessage: nil
        )

        let issues = ProjectHealthAnalyzer.issues(snapshot: snapshot) { _, _ in .unknown }

        XCTAssertEqual(issues.count, 1)
        XCTAssertNil(issues.first?.fix)
        XCTAssertEqual(issues.first?.severity, .warning)
    }
}
