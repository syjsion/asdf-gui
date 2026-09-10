import XCTest
@testable import AsdfGUI

final class ShellIntegrationTests: XCTestCase {
    func testDetectsSupportedShells() {
        XCTAssertEqual(SupportedShell.detect(from: "/bin/zsh"), .zsh)
        XCTAssertEqual(SupportedShell.detect(from: "/opt/homebrew/bin/bash"), .bash)
        XCTAssertNil(SupportedShell.detect(from: "/opt/homebrew/bin/fish"))
    }

    func testZshPlanUsesZshrcAndAddsExecutableAndShimsPaths() throws {
        let home = try temporaryHome()
        let service = ShellIntegrationService(homeDirectory: home)
        let executable = home.appendingPathComponent(".local/bin/asdf")

        let plan = try service.plan(shell: .zsh, executableURL: executable)

        XCTAssertEqual(plan.configurationURL, home.appendingPathComponent(".zshrc"))
        XCTAssertEqual(plan.status, .notConfigured)
        XCTAssertTrue(plan.managedBlock.contains("export PATH='\(home.path)/.local/bin':\"$PATH\""))
        XCTAssertTrue(plan.managedBlock.contains("${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"))
    }

    func testBashPlanUsesBashProfile() throws {
        let home = try temporaryHome()
        let service = ShellIntegrationService(homeDirectory: home)
        let plan = try service.plan(
            shell: .bash,
            executableURL: URL(fileURLWithPath: "/usr/local/bin/asdf")
        )

        XCTAssertEqual(plan.configurationURL.lastPathComponent, ".bash_profile")
    }

    func testApplyPreservesExistingContentAndBecomesConfigured() throws {
        let home = try temporaryHome()
        let rc = home.appendingPathComponent(".zshrc")
        try "export EDITOR=vim\n".write(to: rc, atomically: true, encoding: .utf8)

        let service = ShellIntegrationService(homeDirectory: home)
        let executable = home.appendingPathComponent(".local/bin/asdf")
        let plan = try service.plan(shell: .zsh, executableURL: executable)
        try service.apply(plan)

        let contents = try String(contentsOf: rc, encoding: .utf8)
        XCTAssertTrue(contents.contains("export EDITOR=vim"))
        XCTAssertTrue(contents.contains(ShellIntegrationService.beginMarker))
        XCTAssertEqual(try service.plan(shell: .zsh, executableURL: executable).status, .configured)
    }

    func testChangingExecutableUpdatesManagedBlockWithoutDuplicatingMarkers() throws {
        let home = try temporaryHome()
        let service = ShellIntegrationService(homeDirectory: home)
        let first = URL(fileURLWithPath: "/opt/homebrew/bin/asdf")
        try service.apply(service.plan(shell: .zsh, executableURL: first))

        let second = home.appendingPathComponent(".local/bin/asdf")
        let update = try service.plan(shell: .zsh, executableURL: second)
        XCTAssertEqual(update.status, .needsUpdate)
        try service.apply(update)

        let contents = try String(contentsOf: home.appendingPathComponent(".zshrc"), encoding: .utf8)
        XCTAssertEqual(contents.components(separatedBy: ShellIntegrationService.beginMarker).count - 1, 1)
        XCTAssertTrue(contents.contains("\(home.path)/.local/bin"))
        XCTAssertFalse(contents.contains("/opt/homebrew/bin':\"$PATH\""))
    }

    func testRemoveOnlyRemovesManagedBlock() throws {
        let home = try temporaryHome()
        let rc = home.appendingPathComponent(".zshrc")
        try "before\nafter\n".write(to: rc, atomically: true, encoding: .utf8)
        let service = ShellIntegrationService(homeDirectory: home)
        let executable = URL(fileURLWithPath: "/usr/local/bin/asdf")
        try service.apply(service.plan(shell: .zsh, executableURL: executable))

        let configured = try service.plan(shell: .zsh, executableURL: executable)
        try service.remove(configured)

        let contents = try String(contentsOf: rc, encoding: .utf8)
        XCTAssertTrue(contents.contains("before"))
        XCTAssertTrue(contents.contains("after"))
        XCTAssertFalse(contents.contains(ShellIntegrationService.beginMarker))
    }

    func testApplyRejectsFileChangedAfterPreview() throws {
        let home = try temporaryHome()
        let rc = home.appendingPathComponent(".zshrc")
        try "one\n".write(to: rc, atomically: true, encoding: .utf8)
        let service = ShellIntegrationService(homeDirectory: home)
        let plan = try service.plan(shell: .zsh, executableURL: URL(fileURLWithPath: "/usr/local/bin/asdf"))
        try "two\n".write(to: rc, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try service.apply(plan)) { error in
            guard case ShellIntegrationError.configurationChanged = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testMalformedManagedBlockIsRejected() throws {
        let home = try temporaryHome()
        let rc = home.appendingPathComponent(".zshrc")
        try "\(ShellIntegrationService.beginMarker)\n".write(to: rc, atomically: true, encoding: .utf8)
        let service = ShellIntegrationService(homeDirectory: home)

        XCTAssertThrowsError(
            try service.plan(shell: .zsh, executableURL: URL(fileURLWithPath: "/usr/local/bin/asdf"))
        )
    }

    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
