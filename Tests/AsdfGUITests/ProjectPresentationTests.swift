import XCTest
@testable import AsdfGUI

final class ProjectPresentationTests: XCTestCase {
    func testFavoritesArePinnedAheadOfNormalSort() {
        let alpha = snapshot(path: "/tmp/alpha", tools: ["nodejs"])
        let beta = snapshot(path: "/tmp/beta", tools: ["python", "ruby"])

        let result = ProjectListPlanner.displayedSnapshots(
            [alpha, beta],
            searchText: "",
            scope: .all,
            sortOrder: .name,
            favoritePaths: [beta.project.path],
            lastUsedDates: [:]
        )

        XCTAssertEqual(result.map(\.project.path), [beta.project.path, alpha.project.path])
    }

    func testFavoritesScopeFiltersNonFavorites() {
        let alpha = snapshot(path: "/tmp/alpha", tools: ["nodejs"])
        let beta = snapshot(path: "/tmp/beta", tools: ["python"])

        let result = ProjectListPlanner.displayedSnapshots(
            [alpha, beta],
            searchText: "",
            scope: .favorites,
            sortOrder: .name,
            favoritePaths: [alpha.project.path],
            lastUsedDates: [:]
        )

        XCTAssertEqual(result.map(\.project.path), [alpha.project.path])
    }

    func testRecentSortUsesLatestActivityThenName() {
        let alpha = snapshot(path: "/tmp/alpha", tools: ["nodejs"])
        let beta = snapshot(path: "/tmp/beta", tools: ["python"])
        let gamma = snapshot(path: "/tmp/gamma", tools: ["ruby"])
        let now = Date(timeIntervalSince1970: 2_000)

        let result = ProjectListPlanner.displayedSnapshots(
            [alpha, beta, gamma],
            searchText: "",
            scope: .all,
            sortOrder: .recent,
            favoritePaths: [],
            lastUsedDates: [
                alpha.project.path: now.addingTimeInterval(-60),
                beta.project.path: now
            ]
        )

        XCTAssertEqual(
            result.map(\.project.path),
            [beta.project.path, alpha.project.path, gamma.project.path]
        )
    }

    func testSearchStillMatchesToolsInsideFavoritesScope() {
        let alpha = snapshot(path: "/tmp/alpha", tools: ["nodejs"])
        let beta = snapshot(path: "/tmp/beta", tools: ["python"])

        let result = ProjectListPlanner.displayedSnapshots(
            [alpha, beta],
            searchText: "node",
            scope: .favorites,
            sortOrder: .name,
            favoritePaths: [alpha.project.path, beta.project.path],
            lastUsedDates: [:]
        )

        XCTAssertEqual(result.map(\.project.path), [alpha.project.path])
    }

    private func snapshot(path: String, tools: [String]) -> ProjectSnapshot {
        ProjectSnapshot(
            project: ManagedProject(path: path),
            hasToolVersionsFile: true,
            requirements: tools.map { ToolRequirement(tool: $0, versions: ["1.0.0"]) },
            errorMessage: nil
        )
    }
}
