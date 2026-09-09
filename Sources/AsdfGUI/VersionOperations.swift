import Foundation

enum VersionOperationKind: Hashable {
    case install
    case uninstall
}

enum VersionOperationStatus: Hashable {
    case running
    case succeeded
    case failed
    case cancelled
}

struct VersionOperationTaskState: Identifiable {
    let id: UUID
    let kind: VersionOperationKind
    let tool: String
    let version: String
    var status: VersionOperationStatus
    var log: String
    var errorMessage: String?

    var isRunning: Bool { status == .running }
}

enum VersionUsageInspector {
    static func projectsUsing(
        tool: String,
        version: String,
        snapshots: [ProjectSnapshot]
    ) -> [ManagedProject] {
        snapshots.compactMap { snapshot in
            let isUsed = snapshot.requirements.contains { requirement in
                requirement.tool == tool && requirement.versions.contains(version)
            }
            return isUsed ? snapshot.project : nil
        }
    }
}
