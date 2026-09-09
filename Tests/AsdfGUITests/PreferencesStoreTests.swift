import XCTest
@testable import AsdfGUI

final class PreferencesStoreTests: XCTestCase {
    func testExecutableAndProjectsRoundTrip() {
        let suiteName = "asdf-gui-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(defaults: defaults)
        let executable = URL(fileURLWithPath: "/tmp/asdf")
        let projects = [
            ManagedProject(path: "/tmp/project-a"),
            ManagedProject(path: "/tmp/project-b")
        ]

        store.setExecutableURL(executable)
        store.setProjects(projects)

        XCTAssertEqual(store.executableURL()?.path, executable.path)
        XCTAssertEqual(store.projects(), projects)

        store.setExecutableURL(nil)
        XCTAssertNil(store.executableURL())
    }
}
