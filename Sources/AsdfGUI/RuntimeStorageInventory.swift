import Foundation
import Observation

enum RuntimeStorageInventoryScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case noManagedReferences

    var id: String { rawValue }
}

enum RuntimeStorageInventorySortOrder: String, CaseIterable, Identifiable, Sendable {
    case largest
    case tool

    var id: String { rawValue }
}

enum RuntimeStorageInventoryPlanner {
    static func displayedEntries(
        _ entries: [RuntimeStorageEntry],
        searchText: String,
        scope: RuntimeStorageInventoryScope,
        sortOrder: RuntimeStorageInventorySortOrder,
        referencedEntryIDs: Set<String>
    ) -> [RuntimeStorageEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = entries.filter { entry in
            let matchesScope = scope == .all || !referencedEntryIDs.contains(entry.id)
            guard matchesScope else { return false }

            return query.isEmpty
                || entry.tool.localizedCaseInsensitiveContains(query)
                || entry.version.localizedCaseInsensitiveContains(query)
                || (entry.path?.localizedCaseInsensitiveContains(query) ?? false)
        }

        return filtered.sorted { lhs, rhs in
            switch sortOrder {
            case .largest:
                let left = lhs.allocatedBytes ?? -1
                let right = rhs.allocatedBytes ?? -1
                if left != right { return left > right }
                if lhs.tool != rhs.tool {
                    return lhs.tool.localizedCaseInsensitiveCompare(rhs.tool) == .orderedAscending
                }
                return lhs.version.localizedStandardCompare(rhs.version) == .orderedDescending
            case .tool:
                let toolOrder = lhs.tool.localizedCaseInsensitiveCompare(rhs.tool)
                if toolOrder != .orderedSame { return toolOrder == .orderedAscending }
                return lhs.version.localizedStandardCompare(rhs.version) == .orderedDescending
            }
        }
    }
}

@MainActor
@Observable
final class RuntimeStorageInventoryModel {
    var entries: [RuntimeStorageEntry] = []
    var toolErrors: [String: String] = [:]
    var isScanning = false
    var scannedAt: Date?
    var errorMessage: String?

    private let service: AsdfService
    private var requestID = UUID()

    init(service: AsdfService = AsdfService()) {
        self.service = service
    }

    var totalAllocatedBytes: Int64 {
        entries.compactMap(\.allocatedBytes).reduce(0, +)
    }

    var measuredVersionCount: Int {
        entries.filter { $0.allocatedBytes != nil }.count
    }

    func scan(tools: [String], executableURL: URL?) async {
        let request = UUID()
        requestID = request
        entries = []
        toolErrors = [:]
        scannedAt = nil
        errorMessage = nil

        guard let executableURL else {
            errorMessage = "asdf executable is not available."
            return
        }

        let normalizedTools = Array(Set(tools)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        guard !normalizedTools.isEmpty else {
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
        var errors: [String: String] = [:]

        for tool in normalizedTools {
            if Task.isCancelled || requestID != request { return }

            let versions: [String]
            do {
                versions = try await service.installedVersions(executable: executableURL, tool: tool)
            } catch is CancellationError {
                return
            } catch {
                errors[tool] = error.localizedDescription
                toolErrors = errors
                continue
            }

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
        }

        guard requestID == request else { return }
        toolErrors = errors
        scannedAt = Date()
    }
}
