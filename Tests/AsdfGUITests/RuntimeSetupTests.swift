import Foundation
import XCTest
@testable import AsdfGUI

final class RuntimeSetupTests: XCTestCase {
    func testCatalogResolutionRequiresExactName() {
        let catalog = [
            AsdfPluginCatalogEntry(name: "nodejs", url: "https://example.com/nodejs.git"),
            AsdfPluginCatalogEntry(name: "node", url: "https://example.com/node.git")
        ]

        XCTAssertEqual(
            RuntimeSetupPlanner.exactCatalogEntry(named: "NODEJS", catalog: catalog)?.name,
            "nodejs"
        )
        XCTAssertEqual(
            RuntimeSetupPlanner.exactCatalogEntry(named: "node", catalog: catalog)?.name,
            "node"
        )
        XCTAssertNil(RuntimeSetupPlanner.exactCatalogEntry(named: "nodej", catalog: catalog))
    }

    func testPluginInstallPlanningUsesInstalledPlugins() {
        let plugins = [AsdfPlugin(name: "nodejs", url: nil)]
        XCTAssertFalse(RuntimeSetupPlanner.needsPluginInstall(tool: "nodejs", plugins: plugins))
        XCTAssertFalse(RuntimeSetupPlanner.needsPluginInstall(tool: "NODEJS", plugins: plugins))
        XCTAssertTrue(RuntimeSetupPlanner.needsPluginInstall(tool: "python", plugins: plugins))
    }

    func testRuntimeInstallPlanningSkipsExactInstalledVersionOnly() {
        let installed = ["nodejs": ["22.23.2", "24.8.0"]]
        XCTAssertFalse(
            RuntimeSetupPlanner.shouldInstallVersion(
                tool: "nodejs",
                version: "22.23.2",
                installedVersionsByTool: installed
            )
        )
        XCTAssertTrue(
            RuntimeSetupPlanner.shouldInstallVersion(
                tool: "nodejs",
                version: "22.23.3",
                installedVersionsByTool: installed
            )
        )
    }

    func testRefreshToolsIncludesEveryInstalledPluginOnce() {
        let plugins = [
            AsdfPlugin(name: "python", url: nil),
            AsdfPlugin(name: "nodejs", url: nil),
            AsdfPlugin(name: "python", url: "https://example.com/python.git")
        ]
        XCTAssertEqual(RuntimeSetupPlanner.refreshTools(plugins: plugins), ["nodejs", "python"])
    }

    @MainActor
    func testProjectActivityModelsSynchronizePreferenceChanges() async throws {
        let suiteName = "RuntimeSetupTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PreferencesStore(defaults: defaults)
        let first = ProjectActivityModel(preferences: store)
        let second = ProjectActivityModel(preferences: store)
        let project = ManagedProject(path: "/tmp/asdf-gui-runtime-setup-test")

        first.toggleFavorite(project)
        first.markUsed(project, at: Date(timeIntervalSince1970: 1234))

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(second.isFavorite(project))
        XCTAssertEqual(second.lastUsedDates[project.path]?.timeIntervalSince1970, 1234)
    }
}
