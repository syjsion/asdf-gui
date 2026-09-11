import XCTest
@testable import AsdfGUI

final class AppNavigationTests: XCTestCase {
    @MainActor
    func testSectionsHaveStableKeyboardShortcutOrder() {
        XCTAssertEqual(AppSection.allCases.map(\.shortcutNumber), ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(AppSection.allCases.map(\.rawValue), ["overview", "projects", "versions", "resolution", "plugins", "tools"])
    }

    @MainActor
    func testShowProjectNavigatesAndCreatesOneShotSearchRequest() {
        let navigation = AppNavigationModel()
        let project = ManagedProject(path: "/tmp/example-project")

        navigation.showProject(project)

        XCTAssertEqual(navigation.section, .projects)
        XCTAssertEqual(navigation.consumeProjectSearchRequest(), project.path)
        XCTAssertNil(navigation.consumeProjectSearchRequest())
    }

    @MainActor
    func testShowVersionsNavigatesAndCreatesOneShotToolRequest() {
        let navigation = AppNavigationModel()

        navigation.showVersions(tool: "nodejs")

        XCTAssertEqual(navigation.section, .versions)
        XCTAssertEqual(navigation.consumeVersionToolRequest(), "nodejs")
        XCTAssertNil(navigation.consumeVersionToolRequest())
    }
}
