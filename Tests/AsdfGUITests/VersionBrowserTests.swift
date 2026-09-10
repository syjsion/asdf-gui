import XCTest
@testable import AsdfGUI

final class VersionBrowserTests: XCTestCase {
    func testCatalogMergesAvailableInstalledAndLatestWithoutDuplicates() {
        let records = VersionCatalog.records(
            available: ["20.19.5", "22.19.0", "24.7.0"],
            installed: ["18.20.8", "22.19.0"],
            latest: "24.7.0"
        )

        XCTAssertEqual(records.map(\.version), ["18.20.8", "22.19.0", "20.19.5", "24.7.0"])
        XCTAssertTrue(records[0].isInstalled)
        XCTAssertTrue(records[1].isInstalled)
        XCTAssertFalse(records[2].isInstalled)
        XCTAssertTrue(records[3].isLatest)
    }

    func testCatalogKeepsAllInstalledVersionsBeforeLargeAvailableCatalog() {
        let available = (1...100).map { "1.0.\($0)" }
        let records = VersionCatalog.records(
            available: available,
            installed: ["0.9.0", "1.0.50"],
            latest: "1.0.100"
        )

        XCTAssertEqual(Array(records.prefix(2).map(\.version)), ["0.9.0", "1.0.50"])
        XCTAssertTrue(records[0].isInstalled)
        XCTAssertTrue(records[1].isInstalled)
    }

    func testCatalogKeepsLatestWhenNotReturnedByAvailableList() {
        let records = VersionCatalog.records(
            available: ["3.12.9", "3.13.2"],
            installed: [],
            latest: "3.13.3"
        )

        XCTAssertEqual(records.map(\.version), ["3.12.9", "3.13.2", "3.13.3"])
        XCTAssertTrue(records.last?.isLatest == true)
    }

    func testCatalogDeduplicatesRepeatedInputs() {
        let records = VersionCatalog.records(
            available: ["1.0.0", "1.0.0"],
            installed: ["1.0.0", "1.0.0"],
            latest: "1.0.0"
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertTrue(records[0].isInstalled)
        XCTAssertTrue(records[0].isLatest)
    }
}
