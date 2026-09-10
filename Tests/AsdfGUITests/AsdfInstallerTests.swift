import XCTest
@testable import AsdfGUI

final class AsdfInstallerTests: XCTestCase {
    func testReleaseResolverSelectsExpectedDarwinAsset() throws {
        let release = AsdfGitHubRelease(
            tagName: "v0.20.0",
            assets: [
                .init(
                    name: "asdf-v0.20.0-darwin-arm64.tar.gz",
                    browserDownloadURL: URL(string: "https://example.com/arm64.tar.gz")!,
                    digest: "sha256:" + String(repeating: "a", count: 64)
                ),
                .init(
                    name: "asdf-v0.20.0-darwin-amd64.tar.gz",
                    browserDownloadURL: URL(string: "https://example.com/amd64.tar.gz")!,
                    digest: "sha256:" + String(repeating: "b", count: 64)
                )
            ]
        )

        let arm64 = try AsdfReleaseResolver.asset(in: release, architecture: "arm64")
        let amd64 = try AsdfReleaseResolver.asset(in: release, architecture: "amd64")

        XCTAssertEqual(arm64.name, "asdf-v0.20.0-darwin-arm64.tar.gz")
        XCTAssertEqual(amd64.name, "asdf-v0.20.0-darwin-amd64.tar.gz")
        XCTAssertEqual(release.version, "0.20.0")
    }

    func testReleaseResolverRejectsMissingArchitectureAsset() {
        let release = AsdfGitHubRelease(tagName: "v0.20.0", assets: [])

        XCTAssertThrowsError(try AsdfReleaseResolver.asset(in: release, architecture: "arm64")) { error in
            guard case AsdfInstallerError.releaseHasNoMatchingAsset(let name) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(name, "asdf-v0.20.0-darwin-arm64.tar.gz")
        }
    }

    func testSHA256DigestRequiresGitHubSHA256Format() throws {
        let value = String(repeating: "C", count: 64)
        XCTAssertEqual(
            try AsdfReleaseResolver.sha256(from: "sha256:\(value)"),
            value.lowercased()
        )

        XCTAssertThrowsError(try AsdfReleaseResolver.sha256(from: nil))
        XCTAssertThrowsError(try AsdfReleaseResolver.sha256(from: "md5:abc"))
        XCTAssertThrowsError(try AsdfReleaseResolver.sha256(from: "sha256:not-a-digest"))
    }

    func testDefaultDestinationUsesLocalBin() {
        let destination = AsdfInstaller().defaultDestinationURL()
        XCTAssertTrue(destination.path.hasSuffix("/.local/bin/asdf"))
    }
}
