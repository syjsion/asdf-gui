import XCTest
@testable import AsdfGUI

final class AppUpdateTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertLessThan(SemanticVersion("v0.1.9")!, SemanticVersion("0.2.0")!)
        XCTAssertLessThan(SemanticVersion("1.9.9")!, SemanticVersion("2.0.0")!)
        XCTAssertEqual(SemanticVersion("v1.2.3-beta.1"), SemanticVersion("1.2.3"))
    }

    func testResolverIncludesPrereleasesAndChoosesNewestSemanticVersion() {
        let releases = [
            release(tag: "v0.1.0", prerelease: true, assets: []),
            release(tag: "v0.2.0", prerelease: true, assets: [
                asset(name: "asdf-gui-0.2.0-macos-arm64-adhoc.dmg", url: "https://example.com/arm64.dmg")
            ])
        ]

        let result = AppUpdateResolver.resolve(
            currentVersion: "0.1.0",
            releases: releases,
            architecture: .arm64
        )

        guard case .updateAvailable(let update) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(update.version, "v0.2.0")
        XCTAssertTrue(update.prerelease)
        XCTAssertEqual(update.downloadURL?.absoluteString, "https://example.com/arm64.dmg")
    }

    func testResolverSelectsArchitectureSpecificDMG() {
        let releases = [release(tag: "v1.0.0", prerelease: false, assets: [
            asset(name: "asdf-gui-1.0.0-macos-arm64-developer-id.dmg", url: "https://example.com/arm.dmg"),
            asset(name: "asdf-gui-1.0.0-macos-x86_64-developer-id.dmg", url: "https://example.com/intel.dmg")
        ])]

        let arm = AppUpdateResolver.resolve(currentVersion: "0.9.0", releases: releases, architecture: .arm64)
        let intel = AppUpdateResolver.resolve(currentVersion: "0.9.0", releases: releases, architecture: .x86_64)

        guard case .updateAvailable(let armUpdate) = arm,
              case .updateAvailable(let intelUpdate) = intel else {
            return XCTFail("Expected updates for both architectures")
        }
        XCTAssertEqual(armUpdate.downloadURL?.lastPathComponent, "arm.dmg")
        XCTAssertEqual(intelUpdate.downloadURL?.lastPathComponent, "intel.dmg")
    }

    func testResolverIgnoresDraftAndReportsUpToDate() {
        let releases = [
            release(tag: "v9.0.0", draft: true, prerelease: false, assets: []),
            release(tag: "v0.2.0", prerelease: true, assets: [])
        ]

        let result = AppUpdateResolver.resolve(
            currentVersion: "0.2.0",
            releases: releases,
            architecture: .arm64
        )

        XCTAssertEqual(result, .upToDate(latestVersion: "v0.2.0"))
    }

    private func release(
        tag: String,
        draft: Bool = false,
        prerelease: Bool,
        assets: [AppReleaseAsset]
    ) -> AppRelease {
        AppRelease(
            tagName: tag,
            name: tag,
            htmlURL: URL(string: "https://github.com/syjsion/asdf-gui/releases/tag/\(tag)")!,
            draft: draft,
            prerelease: prerelease,
            assets: assets
        )
    }

    private func asset(name: String, url: String) -> AppReleaseAsset {
        AppReleaseAsset(name: name, browserDownloadURL: URL(string: url)!)
    }
}
