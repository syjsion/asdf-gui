import Foundation

struct ManagedProject: Identifiable, Hashable {
    let path: String

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String {
        let value = url.lastPathComponent
        return value.isEmpty ? path : value
    }
}

struct ToolRequirement: Identifiable, Hashable {
    let tool: String
    let versions: [String]

    var id: String { tool }
}

struct ProjectSnapshot: Identifiable, Hashable {
    let project: ManagedProject
    let hasToolVersionsFile: Bool
    let requirements: [ToolRequirement]
    let errorMessage: String?

    var id: String { project.id }
}

enum ToolVersionsParser {
    static func parse(_ contents: String) -> [ToolRequirement] {
        contents
            .split(whereSeparator: { $0.isNewline })
            .compactMap { rawLine in
                let lineWithoutComment = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? rawLine
                let parts = lineWithoutComment
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)

                guard parts.count >= 2 else { return nil }
                return ToolRequirement(tool: parts[0], versions: Array(parts.dropFirst()))
            }
    }
}

struct ProjectService {
    private let fileManager = FileManager.default

    func snapshot(for project: ManagedProject) -> ProjectSnapshot {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: project.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ProjectSnapshot(
                project: project,
                hasToolVersionsFile: false,
                requirements: [],
                errorMessage: "Project folder no longer exists."
            )
        }

        let toolVersionsURL = project.url.appendingPathComponent(".tool-versions")
        guard fileManager.fileExists(atPath: toolVersionsURL.path) else {
            return ProjectSnapshot(
                project: project,
                hasToolVersionsFile: false,
                requirements: [],
                errorMessage: nil
            )
        }

        do {
            let contents = try String(contentsOf: toolVersionsURL, encoding: .utf8)
            return ProjectSnapshot(
                project: project,
                hasToolVersionsFile: true,
                requirements: ToolVersionsParser.parse(contents),
                errorMessage: nil
            )
        } catch {
            return ProjectSnapshot(
                project: project,
                hasToolVersionsFile: true,
                requirements: [],
                errorMessage: error.localizedDescription
            )
        }
    }
}
