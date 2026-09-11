import Foundation
import XCTest
@testable import AsdfGUI

final class AppUpdateInstallerTests: XCTestCase {
    func testTrustedReleaseAssetURLRequiresOfficialRepository() {
        let trusted = URL(string: "https://github.com/syjsion/asdf-gui/releases/download/v0.7.0/asdf-gui-0.7.0-macos-arm64-adhoc.dmg")!
        let wrongRepository = URL(string: "https://github.com/other/asdf-gui/releases/download/v0.7.0/asdf-gui-0.7.0-macos-arm64-adhoc.dmg")!
        let insecure = URL(string: "http://github.com/syjsion/asdf-gui/releases/download/v0.7.0/asdf-gui-0.7.0-macos-arm64-adhoc.dmg")!

        XCTAssertTrue(AppUpdateSecurity.trustedReleaseAssetURL(trusted))
        XCTAssertFalse(AppUpdateSecurity.trustedReleaseAssetURL(wrongRepository))
        XCTAssertFalse(AppUpdateSecurity.trustedReleaseAssetURL(insecure))
    }

    func testDigestNormalizationRequiresSHA256Shape() {
        let digest = String(repeating: "a", count: 64)
        XCTAssertEqual(AppUpdateSecurity.normalizedSHA256("sha256:\(digest)"), digest)
        XCTAssertEqual(AppUpdateSecurity.normalizedSHA256(digest.uppercased()), digest)
        XCTAssertNil(AppUpdateSecurity.normalizedSHA256("sha256:1234"))
        XCTAssertNil(AppUpdateSecurity.normalizedSHA256("sha512:\(digest)"))
        XCTAssertNil(AppUpdateSecurity.normalizedSHA256(nil))
    }

    func testFileSHA256MatchesKnownDigest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("payload.bin")
        try Data("asdf-gui-update".utf8).write(to: file)

        XCTAssertEqual(
            try AppUpdateSecurity.sha256Hex(ofFileAt: file),
            "f831e67912baa866a5c9d942e71c7bd2797381376209829874cf6242c5237613"
        )
    }

    func testReplacementHelperUsesOnlyPositionalPathsAndRestoresBackupOnFailure() {
        let script = AppUpdateInstaller.replacementHelperScript
        XCTAssertTrue(script.contains("STAGED=\"$2\""))
        XCTAssertTrue(script.contains("TARGET=\"$3\""))
        XCTAssertTrue(script.contains("/usr/bin/ditto \"$STAGED\" \"$TARGET\""))
        XCTAssertTrue(script.contains("/bin/mv \"$BACKUP\" \"$TARGET\""))
        XCTAssertFalse(script.contains("curl"))
        XCTAssertFalse(script.contains("xattr"))
        XCTAssertFalse(script.contains("sudo"))
    }
}
