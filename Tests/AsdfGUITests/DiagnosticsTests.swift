import XCTest
@testable import AsdfGUI

final class DiagnosticsTests: XCTestCase {
    func testDiagnosticCommandsUseExpectedArguments() async throws {
        let fixture = try makeCaptureExecutable()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let service = AsdfService()

        _ = try await service.wherePath(executable: fixture.executable, tool: "nodejs", version: "22.18.0")
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["where", "nodejs", "22.18.0"])

        _ = try await service.whichPath(executable: fixture.executable, command: "node")
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["which", "node"])

        _ = try await service.reshim(executable: fixture.executable, tool: "nodejs", version: "22.18.0")
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["reshim", "nodejs", "22.18.0"])

        _ = try await service.info(executable: fixture.executable)
        XCTAssertEqual(try capturedArguments(fixture.arguments), ["info"])
    }

    func testDiagnosticReportIncludesEnvironmentHeaderAndInfo() {
        let report = DiagnosticReportBuilder.build(
            asdfVersion: "v0.20.0",
            executablePath: "/opt/homebrew/bin/asdf",
            infoOutput: "OS: Darwin\nSHELL: zsh\n"
        )

        XCTAssertTrue(report.contains("asdf GUI Diagnostic Report"))
        XCTAssertTrue(report.contains("asdf: v0.20.0"))
        XCTAssertTrue(report.contains("executable: /opt/homebrew/bin/asdf"))
        XCTAssertTrue(report.contains("OS: Darwin"))
        XCTAssertTrue(report.contains("SHELL: zsh"))
    }

    private func capturedArguments(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
    }

    private func makeCaptureExecutable() throws -> (root: URL, executable: URL, arguments: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-asdf")
        let arguments = root.appendingPathComponent("arguments.txt")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(arguments.path)'
        printf 'fixture output\\n'
        exit 0
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, executable, arguments)
    }
}
