import Foundation

enum ProjectToolVersionsError: LocalizedError {
    case operationInProgress
    case executableUnavailable
    case configurationFileMissing
    case toolNotFound(String)
    case duplicateToolEntries(String)
    case configurationChanged(String)
    case invalidTool(String)
    case invalidVersion(String)

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return "Another asdf write operation is currently running. Finish or cancel it before changing .tool-versions."
        case .executableUnavailable:
            return "asdf executable is not available. Configure it in Settings first."
        case .configurationFileMissing:
            return "The project does not have a .tool-versions file yet. Add a tool first to create it through asdf set."
        case .toolNotFound(let tool):
            return "The \(tool) entry no longer exists in .tool-versions. Refresh the project before trying again."
        case .duplicateToolEntries(let tool):
            return ".tool-versions contains more than one \(tool) entry. Resolve the duplicate entries before removing this tool from asdf GUI."
        case .configurationChanged(let tool):
            return "The \(tool) entry changed after this view was loaded. Refresh the project before removing it."
        case .invalidTool(let value):
            return "Invalid tool name: \(value). Tool names cannot be empty or contain whitespace."
        case .invalidVersion(let value):
            return "Invalid version value: \(value). Version entries cannot be empty or contain whitespace."
        }
    }
}

struct ProjectToolVersionCatalog: Hashable {
    let installed: [String]
    let available: [String]
    let latest: String?

    var records: [ToolVersionRecord] {
        VersionCatalog.records(available: available, installed: installed, latest: latest)
    }
}

struct ToolVersionsMutationService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func removeTool(
        project: ManagedProject,
        tool: String,
        expectedVersions: [String]
    ) throws {
        let url = project.url.appendingPathComponent(".tool-versions")
        guard fileManager.fileExists(atPath: url.path) else {
            throw ProjectToolVersionsError.configurationFileMissing
        }

        let original = try String(contentsOf: url, encoding: .utf8)
        let updated = try Self.removingTool(
            from: original,
            tool: tool,
            expectedVersions: expectedVersions
        )

        guard updated != original else { return }

        let permissions = (try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions])
        try updated.write(to: url, atomically: true, encoding: .utf8)
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    static func removingTool(
        from contents: String,
        tool: String,
        expectedVersions: [String]
    ) throws -> String {
        let nsContents = contents as NSString
        var location = 0
        var matches: [(range: NSRange, versions: [String])] = []

        while location < nsContents.length {
            let range = nsContents.lineRange(for: NSRange(location: location, length: 0))
            let line = nsContents.substring(with: range)
            if let entry = parseEntry(line), entry.tool == tool {
                matches.append((range: range, versions: entry.versions))
            }
            location = NSMaxRange(range)
        }

        guard !matches.isEmpty else {
            throw ProjectToolVersionsError.toolNotFound(tool)
        }
        guard matches.count == 1 else {
            throw ProjectToolVersionsError.duplicateToolEntries(tool)
        }
        guard matches[0].versions == expectedVersions else {
            throw ProjectToolVersionsError.configurationChanged(tool)
        }

        let mutable = NSMutableString(string: contents)
        mutable.deleteCharacters(in: matches[0].range)
        return mutable as String
    }

    static func validateTool(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw ProjectToolVersionsError.invalidTool(raw)
        }
        return value
    }

    static func validateVersions(_ versions: [String]) throws -> [String] {
        guard !versions.isEmpty else {
            throw ProjectToolVersionsError.invalidVersion("")
        }

        return try versions.map { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
                throw ProjectToolVersionsError.invalidVersion(raw)
            }
            return value
        }
    }

    private static func parseEntry(_ rawLine: String) -> (tool: String, versions: [String])? {
        let line = rawLine.trimmingCharacters(in: .newlines)
        let beforeComment = line.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first ?? Substring(line)
        let parts = beforeComment
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard let tool = parts.first, !tool.isEmpty else { return nil }
        return (tool: tool, versions: Array(parts.dropFirst()))
    }
}

@MainActor
extension AppModel {
    func loadProjectToolVersionCatalog(tool: String) async throws -> ProjectToolVersionCatalog {
        guard let executableURL else { throw ProjectToolVersionsError.executableUnavailable }
        let validatedTool = try ToolVersionsMutationService.validateTool(tool)

        let installed = try await AsdfService().installedVersions(executable: executableURL, tool: validatedTool)
        let available = try await AsdfService().availableVersions(executable: executableURL, tool: validatedTool)
        let latest = try? await AsdfService().latestVersion(executable: executableURL, tool: validatedTool)

        installedVersionsByTool[validatedTool] = installed
        return ProjectToolVersionCatalog(installed: installed, available: available, latest: latest)
    }

    func setProjectToolVersions(
        project: ManagedProject,
        tool: String,
        versions: [String]
    ) async throws {
        guard let executableURL else { throw ProjectToolVersionsError.executableUnavailable }
        guard beginExternalWriteOperation() else { throw ProjectToolVersionsError.operationInProgress }
        defer { endExternalWriteOperation() }

        let validatedTool = try ToolVersionsMutationService.validateTool(tool)
        let validatedVersions = try ToolVersionsMutationService.validateVersions(versions)
        _ = try await AsdfService().setVersion(
            executable: executableURL,
            tool: validatedTool,
            versions: validatedVersions,
            scope: .project(project.url)
        )

        refreshProjects()
        await refreshInstalledVersions()
    }

    func removeProjectToolRequirement(
        project: ManagedProject,
        tool: String,
        expectedVersions: [String]
    ) async throws {
        guard beginExternalWriteOperation() else { throw ProjectToolVersionsError.operationInProgress }
        defer { endExternalWriteOperation() }

        let validatedTool = try ToolVersionsMutationService.validateTool(tool)
        try ToolVersionsMutationService().removeTool(
            project: project,
            tool: validatedTool,
            expectedVersions: expectedVersions
        )
        refreshProjects()
        await refreshInstalledVersions()
    }
}
