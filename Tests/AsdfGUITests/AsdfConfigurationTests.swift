import XCTest
@testable import AsdfGUI

final class AsdfConfigurationTests: XCTestCase {
    func testEmptyConfigurationUsesOfficialDefaults() throws {
        let values = try AsdfConfigService().parse("")
        XCTAssertEqual(values, .defaults)
    }

    func testParsesAllManagedSettings() throws {
        let values = try AsdfConfigService().parse("""
        legacy_version_file = yes
        use_release_candidates = yes
        always_keep_download = yes
        plugin_repository_last_check_duration = never
        disable_plugin_short_name_repository = yes
        concurrency = 8
        """)

        XCTAssertTrue(values.legacyVersionFile)
        XCTAssertTrue(values.useReleaseCandidates)
        XCTAssertTrue(values.alwaysKeepDownload)
        XCTAssertEqual(values.pluginRepositoryLastCheckDuration, .never)
        XCTAssertTrue(values.disablePluginShortNameRepository)
        XCTAssertEqual(values.concurrency, .cores(8))
    }

    func testParsesEveryTriggerSyncInterval() throws {
        let values = try AsdfConfigService().parse("plugin_repository_last_check_duration = 0\n")
        XCTAssertEqual(values.pluginRepositoryLastCheckDuration, .everyTrigger)
    }

    func testUpdatedContentsPreservesUnknownHooksCommentsAndInlineComment() throws {
        let original = """
        # personal configuration
        legacy_version_file = no # keep this explanation
        pre_asdf_install_nodejs = echo preparing
        custom_option = untouched
        """
        var values = AsdfConfigValues.defaults
        values.legacyVersionFile = true
        values.alwaysKeepDownload = true
        values.pluginRepositoryLastCheckDuration = .minutes(15)
        values.concurrency = .cores(6)

        let updated = try AsdfConfigService().updatedContents(original: original, values: values)

        XCTAssertTrue(updated.contains("# personal configuration"))
        XCTAssertTrue(updated.contains("legacy_version_file = yes # keep this explanation"))
        XCTAssertTrue(updated.contains("pre_asdf_install_nodejs = echo preparing"))
        XCTAssertTrue(updated.contains("custom_option = untouched"))
        XCTAssertTrue(updated.contains("always_keep_download = yes"))
        XCTAssertTrue(updated.contains("plugin_repository_last_check_duration = 15"))
        XCTAssertTrue(updated.contains("concurrency = 6"))
    }

    func testDuplicateManagedKeyIsRejected() throws {
        XCTAssertThrowsError(try AsdfConfigService().parse("""
        concurrency = auto
        concurrency = 4
        """)) { error in
            XCTAssertEqual(error as? AsdfConfigError, .duplicateKey("concurrency"))
        }
    }

    func testInvalidManagedValuesAreRejected() throws {
        XCTAssertThrowsError(try AsdfConfigService().parse("legacy_version_file = maybe\n"))
        XCTAssertThrowsError(try AsdfConfigService().parse("plugin_repository_last_check_duration = -1\n"))
        XCTAssertThrowsError(try AsdfConfigService().parse("concurrency = 0\n"))
    }

    func testConfigURLUsesAbsoluteEnvironmentOverride() throws {
        let home = URL(fileURLWithPath: "/tmp/example-home")
        let target = try AsdfConfigService().configURL(
            environment: ["ASDF_CONFIG_FILE": "/tmp/custom/asdf.conf"],
            homeDirectory: home
        )
        XCTAssertTrue(target.overridden)
        XCTAssertEqual(target.url.path, "/tmp/custom/asdf.conf")
    }

    func testConfigURLRejectsRelativeEnvironmentOverride() throws {
        XCTAssertThrowsError(try AsdfConfigService().configURL(
            environment: ["ASDF_CONFIG_FILE": "relative/asdfrc"],
            homeDirectory: URL(fileURLWithPath: "/tmp/home")
        )) { error in
            XCTAssertEqual(error as? AsdfConfigError, .configPathMustBeAbsolute("relative/asdfrc"))
        }
    }

    func testSaveRejectsExternalChangeAndPreservesIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let config = root.appendingPathComponent(".asdfrc")
        try "concurrency = auto\n".write(to: config, atomically: true, encoding: .utf8)
        let service = AsdfConfigService()
        let snapshot = try service.load(environment: [:], homeDirectory: root)

        try "concurrency = 12\n# external edit\n".write(to: config, atomically: true, encoding: .utf8)
        var values = snapshot.values
        values.concurrency = .cores(4)

        XCTAssertThrowsError(try service.save(snapshot: snapshot, values: values)) { error in
            XCTAssertEqual(error as? AsdfConfigError, .configurationChanged)
        }
        XCTAssertEqual(try String(contentsOf: config, encoding: .utf8), "concurrency = 12\n# external edit\n")
    }

    func testSaveCreatesConfigAndPreservesExistingPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = AsdfConfigService()
        var snapshot = try service.load(environment: [:], homeDirectory: root)
        var values = snapshot.values
        values.alwaysKeepDownload = true
        snapshot = try service.save(snapshot: snapshot, values: values)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.url.path))
        XCTAssertTrue(try String(contentsOf: snapshot.url, encoding: .utf8).contains("always_keep_download = yes"))

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshot.url.path)
        snapshot = try service.load(environment: [:], homeDirectory: root)
        values = snapshot.values
        values.legacyVersionFile = true
        _ = try service.save(snapshot: snapshot, values: values)

        let attributes = try FileManager.default.attributesOfItem(atPath: snapshot.url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
