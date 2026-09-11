import Foundation
import Observation

struct RuntimeStorageMeasurement: Hashable, Sendable {
    let allocatedBytes: Int64
    let fileCount: Int
}

struct RuntimeStorageEntry: Identifiable, Hashable, Sendable {
    let tool: String
    let version: String
    let path: String?
    let measurement: RuntimeStorageMeasurement?
    let errorMessage: String?

    var id: String { "\(tool)@\(version)" }
    var allocatedBytes: Int64? { measurement?.allocatedBytes }
}

enum RuntimeStorageError: LocalizedError, Equatable {
    case pathUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .pathUnavailable(let path):
            return "Runtime path is unavailable: \(path)"
        }
    }
}

enum RuntimeStorageSizer {
    static func measure(url: URL) async throws -> RuntimeStorageMeasurement {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager()
            let root = url.standardizedFileURL.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                throw RuntimeStorageError.pathUnavailable(root.path)
            }

            let keys: Set<URLResourceKey> = [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey
            ]

            if !isDirectory.boolValue {
                let values = try root.resourceValues(forKeys: keys)
                return RuntimeStorageMeasurement(
                    allocatedBytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0),
                    fileCount: values.isRegularFile == true ? 1 : 0
                )
            }

            var stack = [root]
            var allocatedBytes: Int64 = 0
            var fileCount = 0

            while let directory = stack.popLast() {
                try Task.checkCancellation()
                let children = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: Array(keys),
                    options: []
                )

                for child in children {
                    try Task.checkCancellation()
                    let values = try child.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true {
                        continue
                    }
                    if values.isDirectory == true {
                        stack.append(child)
                        continue
                    }
                    if values.isRegularFile == true {
                        allocatedBytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                        fileCount += 1
                    }
                }
            }

            return RuntimeStorageMeasurement(allocatedBytes: allocatedBytes, fileCount: fileCount)
        }.value
    }
}

@MainActor
@Observable
final class RuntimeStorageModel {
    var entries: [RuntimeStorageEntry] = []
    var isScanning = false
    var errorMessage: String?
    var scannedAt: Date?

    private let service: AsdfService
    private var requestID = UUID()

    init(service: AsdfService = AsdfService()) {
        self.service = service
    }

    var totalAllocatedBytes: Int64 {
        entries.compactMap(\.allocatedBytes).reduce(0, +)
    }

    func scan(tool: String, versions: [String], executableURL: URL?) async {
        let request = UUID()
        requestID = request
        entries = []
        errorMessage = nil
        scannedAt = nil

        guard let executableURL else {
            errorMessage = "asdf executable is not available."
            return
        }

        guard !versions.isEmpty else {
            scannedAt = Date()
            return
        }

        isScanning = true
        defer {
            if requestID == request {
                isScanning = false
            }
        }

        var scannedEntries: [RuntimeStorageEntry] = []
        for version in versions {
            if Task.isCancelled || requestID != request { return }

            do {
                let path = try await service.wherePath(
                    executable: executableURL,
                    tool: tool,
                    version: version
                )
                if Task.isCancelled || requestID != request { return }

                do {
                    let measurement = try await RuntimeStorageSizer.measure(url: URL(fileURLWithPath: path))
                    scannedEntries.append(RuntimeStorageEntry(
                        tool: tool,
                        version: version,
                        path: path,
                        measurement: measurement,
                        errorMessage: nil
                    ))
                } catch is CancellationError {
                    return
                } catch {
                    scannedEntries.append(RuntimeStorageEntry(
                        tool: tool,
                        version: version,
                        path: path,
                        measurement: nil,
                        errorMessage: error.localizedDescription
                    ))
                }
            } catch is CancellationError {
                return
            } catch {
                scannedEntries.append(RuntimeStorageEntry(
                    tool: tool,
                    version: version,
                    path: nil,
                    measurement: nil,
                    errorMessage: error.localizedDescription
                ))
            }

            guard requestID == request else { return }
            entries = scannedEntries
        }

        guard requestID == request else { return }
        scannedAt = Date()
    }
}
