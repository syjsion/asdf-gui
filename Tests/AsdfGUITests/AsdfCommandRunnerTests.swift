import XCTest
@testable import AsdfGUI

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func append(_ text: String) {
        lock.lock()
        value += text
        lock.unlock()
    }

    func snapshot() -> String {
        lock.lock()
        let result = value
        lock.unlock()
        return result
    }
}

final class AsdfCommandRunnerTests: XCTestCase {
    func testRunStreamsStdoutAndReturnsCompleteResult() async throws {
        let collector = OutputCollector()
        let runner = AsdfCommandRunner()

        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello-stream"]
        ) { event in
            switch event.stream {
            case .stdout:
                collector.append(event.text)
            case .stderr:
                break
            }
        }

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "hello-stream\n")
        XCTAssertTrue(collector.snapshot().contains("hello-stream"))
    }

    func testRunPrependsExecutableDirectoryForNestedAsdfCallbacks() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("asdf-runner-path-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("asdf")
        let script = """
        #!/bin/sh
        if [ "$1" = "nested" ]; then
          printf 'nested-ok\\n'
          exit 0
        fi
        asdf nested
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let runner = AsdfCommandRunner()
        let result = try await runner.run(executable: executable, arguments: ["install"])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "nested-ok\n")
    }

    func testChildEnvironmentPinsSelectedExecutableDirectoryAheadOfExistingPath() {
        let executable = URL(fileURLWithPath: "/custom/asdf/bin/asdf")
        let environment = AsdfCommandRunner.childEnvironment(
            for: executable,
            inherited: ["PATH": "/usr/local/bin:/custom/asdf/bin:/usr/bin", "HOME": "/tmp/home"]
        )

        XCTAssertEqual(environment["PATH"], "/custom/asdf/bin:/usr/local/bin:/usr/bin")
        XCTAssertEqual(environment["HOME"], "/tmp/home")
    }

    func testRunCancellationTerminatesProcess() async throws {
        let runner = AsdfCommandRunner()
        let task = Task {
            try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"]
            )
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}
