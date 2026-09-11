import XCTest
@testable import AsdfGUI

final class PreferencesStoreTests: XCTestCase {
    func testExecutableProjectsAndProjectActivityRoundTrip() {
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
        let favorites: Set<String> = ["/tmp/project-b"]
        let recent = [
            "/tmp/project-a": Date(timeIntervalSince1970: 1_700_000_000),
            "/tmp/project-b": Date(timeIntervalSince1970: 1_700_000_123)
        ]

        store.setExecutableURL(executable)
        store.setProjects(projects)
        store.setFavoriteProjectPaths(favorites)
        store.setProjectLastUsedDates(recent)

        XCTAssertEqual(store.executableURL()?.path, executable.path)
        XCTAssertEqual(store.projects(), projects)
        XCTAssertEqual(store.favoriteProjectPaths(), favorites)
        XCTAssertEqual(store.projectLastUsedDates(), recent)

        store.setExecutableURL(nil)
        XCTAssertNil(store.executableURL())
    }
}
