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

struct ProjectInstallItem: Identifiable, Hashable {
    let tool: String
    let version: String

    var id: String { "\(tool)@\(version)" }
}

enum RequirementVersionStatus: Hashable {
    case installed
    case missing
    case system
    case path
    case pluginMissing
    case unknown

    var isSatisfied: Bool {
        switch self {
        case .installed, .system, .path:
            return true
        case .missing, .pluginMissing, .unknown:
            return false
        }
    }
}

enum RequirementStatusResolver {
    static func resolve(
        version: String,
        installedVersions: Set<String>?,
        pluginInstalled: Bool,
        lookupFailed: Bool
    ) -> RequirementVersionStatus {
        guard pluginInstalled else { return .pluginMissing }
        if version == "system" { return .system }
        if version.hasPrefix("path:") { return .path }
        if lookupFailed { return .unknown }
        guard let installedVersions else { return .unknown }
        return installedVersions.contains(version) ? .installed : .missing
    }
}

enum ProjectInstallPlanner {
    static func plan(
        requirements: [ToolRequirement],
        status: (String, String) -> RequirementVersionStatus
    ) -> [ProjectInstallItem] {
        var seenTools = Set<String>()
        var items: [ProjectInstallItem] = []

        for requirement in requirements where seenTools.insert(requirement.tool).inserted {
            let states = requirement.versions.map { version in
                (version, status(requirement.tool, version))
            }

            if states.contains(where: { $0.1.isSatisfied }) {
                continue
            }

            if let firstInstallable = states.first(where: { $0.1 == .missing }) {
                items.append(ProjectInstallItem(tool: requirement.tool, version: firstInstallable.0))
            }
        }

        return items
    }
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
