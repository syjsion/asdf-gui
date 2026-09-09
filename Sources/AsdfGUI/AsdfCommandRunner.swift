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

            return try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<AsdfCommandResult, Error>) in
                let process = Process()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                let accumulator = OutputAccumulator()
                let stdoutHandle = stdoutPipe.fileHandleForReading
                let stderrHandle = stderrPipe.fileHandleForReading

                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = currentDirectory
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                configureReadHandler(
                    stdoutHandle,
                    stream: .stdout,
                    accumulator: accumulator,
                    onOutput: onOutput
                )
                configureReadHandler(
                    stderrHandle,
                    stream: .stderr,
                    accumulator: accumulator,
                    onOutput: onOutput
                )

                cancellationController.attach(process)

                process.terminationHandler = { process in
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil

                    let stdoutRemainder = stdoutHandle.readDataToEndOfFile()
                    let stderrRemainder = stderrHandle.readDataToEndOfFile()
                    accumulator.append(stdoutRemainder, stream: .stdout)
                    accumulator.append(stderrRemainder, stream: .stderr)
                    emit(stdoutRemainder, stream: .stdout, onOutput: onOutput)
                    emit(stderrRemainder, stream: .stderr, onOutput: onOutput)

                    cancellationController.detach()
                    continuation.resume(returning: accumulator.result(exitCode: process.terminationStatus))
                }

                do {
                    try process.run()
                    cancellationController.terminateIfCancelled()
                } catch {
                    stdoutHandle.readabilityHandler = nil
                    stderrHandle.readabilityHandler = nil
                    process.terminationHandler = nil
                    cancellationController.detach()
                    continuation.resume(throwing: error)
                }
            }
        }, onCancel: {
            cancellationController.cancel()
        })

        try Task.checkCancellation()
        return result
    }

    private func configureReadHandler(
        _ handle: FileHandle,
        stream: AsdfOutputStream,
        accumulator: OutputAccumulator,
        onOutput: @escaping @Sendable (AsdfOutputEvent) -> Void
    ) {
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            accumulator.append(data, stream: stream)
            emit(data, stream: stream, onOutput: onOutput)
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
