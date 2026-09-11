import XCTest
@testable import AsdfGUI

final class RuntimeStorageTests: XCTestCase {
    func testMeasurementCountsNestedFilesAndSkipsSymlinkTargets() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("first.bin")
        let second = nested.appendingPathComponent("second.bin")
        try Data(repeating: 1, count: 8_192).write(to: first)
        try Data(repeating: 2, count: 4_096).write(to: second)

        let symlink = root.appendingPathComponent("duplicate-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: second)

        let measurement = try await RuntimeStorageSizer.measure(url: root)

        XCTAssertEqual(measurement.fileCount, 2)
        XCTAssertGreaterThan(measurement.allocatedBytes, 0)
    }

    func testMeasurementRejectsMissingPath() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            _ = try await RuntimeStorageSizer.measure(url: missing)
            XCTFail("Expected missing runtime path to throw")
        } catch let error as RuntimeStorageError {
            XCTAssertEqual(error, .pathUnavailable(missing.standardizedFileURL.resolvingSymlinksInPath().path))
        }
    }
}
