import Foundation

enum AsdfOutputStream: Sendable {
    case stdout
    case stderr
}

struct AsdfOutputEvent: Sendable {
    let stream: AsdfOutputStream
    let text: String
}

struct AsdfCommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private final class ProcessCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func attach(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let process = self.process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func terminateIfCancelled() {
        lock.lock()
        let shouldTerminate = isCancelled
        let process = self.process
        lock.unlock()

        if shouldTerminate, process?.isRunning == true {
            process?.terminate()
        }
    }

    func detach() {
        lock.lock()
        process = nil
        lock.unlock()
    }
}

private final class ProcessTerminationWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func signal(_ status: Int32) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: status)
        } else {
            self.status = status
            lock.unlock()
        }
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let status {
                lock.unlock()
                continuation.resume(returning: status)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    func append(_ data: Data, stream: AsdfOutputStream) {
        guard !data.isEmpty else { return }
        lock.lock()
        switch stream {
        case .stdout:
            stdout.append(data)
        case .stderr:
            stderr.append(data)
        }
        lock.unlock()
    }

    func result(exitCode: Int32) -> AsdfCommandResult {
        lock.lock()
        let stdout = self.stdout
        let stderr = self.stderr
        lock.unlock()

        return AsdfCommandResult(
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            exitCode: exitCode
        )
    }
}

struct AsdfCommandRunner {
    func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void = { _ in }
    ) async throws -> AsdfCommandResult {
        let cancellationController = ProcessCancellationController()

        let result = try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()

            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let accumulator = OutputAccumulator()
            let terminationWaiter = ProcessTerminationWaiter()

            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.environment = Self.childEnvironment(for: executable)
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.terminationHandler = { process in
                terminationWaiter.signal(process.terminationStatus)
            }

            cancellationController.attach(process)

            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                cancellationController.detach()
                throw error
            }

            cancellationController.terminateIfCancelled()

            async let stdoutDrain: Void = drain(
                stdoutPipe.fileHandleForReading,
                stream: .stdout,
                accumulator: accumulator,
                onOutput: onOutput
            )
            async let stderrDrain: Void = drain(
                stderrPipe.fileHandleForReading,
                stream: .stderr,
                accumulator: accumulator,
                onOutput: onOutput
            )

            let exitCode = await terminationWaiter.wait()

            do {
                _ = try await (stdoutDrain, stderrDrain)
            } catch {
                cancellationController.detach()
                throw error
            }

            cancellationController.detach()
            return accumulator.result(exitCode: exitCode)
        }, onCancel: {
            cancellationController.cancel()
        })

        try Task.checkCancellation()
        return result
    }

    static func childEnvironment(
        for executable: URL,
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = inherited
        let executableDirectory = executable.standardizedFileURL.deletingLastPathComponent().path
        let fallbackPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let existingPath = environment["PATH"]?.isEmpty == false ? environment["PATH"]! : fallbackPath
        let pathEntries = existingPath
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != executableDirectory }

        environment["PATH"] = ([executableDirectory] + pathEntries).joined(separator: ":")
        return environment
    }

    private func drain(
        _ handle: FileHandle,
        stream: AsdfOutputStream,
        accumulator: OutputAccumulator,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    while true {
                        guard let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty else {
                            break
                        }
                        accumulator.append(data, stream: stream)
                        emit(data, stream: stream, onOutput: onOutput)
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private func emit(
    _ data: Data,
    stream: AsdfOutputStream,
    onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
) {
    guard !data.isEmpty else { return }
    onOutput(AsdfOutputEvent(stream: stream, text: String(decoding: data, as: UTF8.self)))
}
