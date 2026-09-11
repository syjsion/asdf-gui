import XCTest
@testable import AsdfGUI

final class RuntimeStorageInventoryTests: XCTestCase {
    func testLargestSortOrdersMeasuredEntriesBeforeFailures() {
        let entries = [
            entry(tool: "python", version: "3.13.0", bytes: 200),
            entry(tool: "nodejs", version: "22.0.0", bytes: 800),
            RuntimeStorageEntry(
                tool: "ruby",
                version: "3.4.0",
                path: nil,
                measurement: nil,
                errorMessage: "missing"
            )
        ]

        let result = RuntimeStorageInventoryPlanner.displayedEntries(
            entries,
            searchText: "",
            scope: .all,
            sortOrder: .largest,
            referencedEntryIDs: []
        )

        XCTAssertEqual(result.map(\.id), ["nodejs@22.0.0", "python@3.13.0", "ruby@3.4.0"])
    }

    func testNoManagedReferencesScopeFiltersKnownReferences() {
        let node = entry(tool: "nodejs", version: "22.0.0", bytes: 800)
        let python = entry(tool: "python", version: "3.13.0", bytes: 200)

        let result = RuntimeStorageInventoryPlanner.displayedEntries(
            [node, python],
            searchText: "",
            scope: .noManagedReferences,
            sortOrder: .largest,
            referencedEntryIDs: [node.id]
        )

        XCTAssertEqual(result.map(\.id), [python.id])
    }

    func testSearchMatchesToolVersionAndInstallPath() {
        let node = RuntimeStorageEntry(
            tool: "nodejs",
            version: "22.0.0",
            path: "/tmp/asdf/installs/nodejs/22.0.0",
            measurement: RuntimeStorageMeasurement(allocatedBytes: 800, fileCount: 1),
            errorMessage: nil
        )
        let python = RuntimeStorageEntry(
            tool: "python",
            version: "3.13.0",
            path: "/tmp/custom-python/runtime",
            measurement: RuntimeStorageMeasurement(allocatedBytes: 200, fileCount: 1),
            errorMessage: nil
        )

        XCTAssertEqual(
            RuntimeStorageInventoryPlanner.displayedEntries(
                [node, python],
                searchText: "22.0",
                scope: .all,
                sortOrder: .tool,
                referencedEntryIDs: []
            ).map(\.id),
            [node.id]
        )

        XCTAssertEqual(
            RuntimeStorageInventoryPlanner.displayedEntries(
                [node, python],
                searchText: "custom-python",
                scope: .all,
                sortOrder: .tool,
                referencedEntryIDs: []
            ).map(\.id),
            [python.id]
        )
    }

    private func entry(tool: String, version: String, bytes: Int64) -> RuntimeStorageEntry {
        RuntimeStorageEntry(
            tool: tool,
            version: version,
            path: "/tmp/\(tool)/\(version)",
            measurement: RuntimeStorageMeasurement(allocatedBytes: bytes, fileCount: 1),
            errorMessage: nil
        )
    }
}
