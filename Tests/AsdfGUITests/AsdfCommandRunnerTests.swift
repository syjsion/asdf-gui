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
