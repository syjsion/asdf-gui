import Foundation

enum SupportedShell: String, CaseIterable, Identifiable, Sendable {
    case zsh
    case bash

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zsh: "Zsh"
        case .bash: "Bash"
        }
    }

    var configurationFilename: String {
        switch self {
        case .zsh: ".zshrc"
        case .bash: ".bash_profile"
        }
    }

    static func detect(from shellPath: String?) -> SupportedShell? {
        guard let shellPath else { return nil }
        switch URL(fileURLWithPath: shellPath).lastPathComponent {
        case "zsh": return .zsh
        case "bash": return .bash
        default: return nil
        }
    }
}

enum ShellIntegrationStatus: Hashable, Sendable {
    case notConfigured
    case configured
    case needsUpdate
}

struct ShellIntegrationPlan: Sendable {
    let shell: SupportedShell
    let configurationURL: URL
    let executableURL: URL
    let managedBlock: String
    let originalContents: String
    let proposedContents: String
    let status: ShellIntegrationStatus
}

enum ShellIntegrationError: LocalizedError {
    case malformedManagedBlock
    case configurationChanged

    var errorDescription: String? {
        switch self {
        case .malformedManagedBlock:
            "The shell configuration contains only one asdf GUI marker. Fix or remove the incomplete managed block before continuing."
        case .configurationChanged:
            "The shell configuration changed after the preview was generated. Refresh the preview before applying changes."
        }
    }
}

struct ShellIntegrationService {
    static let beginMarker = "# >>> asdf GUI shell integration >>>"
    static let endMarker = "# <<< asdf GUI shell integration <<<"

    private let fileManager: FileManager
    private let homeDirectory: URL

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    func configurationURL(for shell: SupportedShell) -> URL {
        homeDirectory.appendingPathComponent(shell.configurationFilename)
    }

    func plan(shell: SupportedShell, executableURL: URL) throws -> ShellIntegrationPlan {
        let configurationURL = configurationURL(for: shell)
        let original = (try? String(contentsOf: configurationURL, encoding: .utf8)) ?? ""
        let block = Self.managedBlock(executableURL: executableURL)
        let range = try managedRange(in: original)

        let proposed: String
        let status: ShellIntegrationStatus

        if let range {
            let existing = String(original[range])
            if existing == block {
                proposed = original
                status = .configured
            } else {
                proposed = original.replacingCharacters(in: range, with: block)
                status = .needsUpdate
            }
        } else {
            proposed = Self.appending(block: block, to: original)
            status = .notConfigured
        }

        return ShellIntegrationPlan(
            shell: shell,
            configurationURL: configurationURL,
            executableURL: executableURL,
            managedBlock: block,
            originalContents: original,
            proposedContents: proposed,
            status: status
        )
    }

    func apply(_ plan: ShellIntegrationPlan) throws {
        let current = (try? String(contentsOf: plan.configurationURL, encoding: .utf8)) ?? ""
        guard current == plan.originalContents else {
            throw ShellIntegrationError.configurationChanged
        }

        try write(plan.proposedContents, to: plan.configurationURL)
    }

    func remove(_ plan: ShellIntegrationPlan) throws {
        let current = (try? String(contentsOf: plan.configurationURL, encoding: .utf8)) ?? ""
        guard current == plan.originalContents else {
            throw ShellIntegrationError.configurationChanged
        }

        guard let range = try managedRange(in: current) else { return }
        var updated = current
        updated.removeSubrange(range)
        updated = Self.normalizeAfterRemoval(updated)
        try write(updated, to: plan.configurationURL)
    }

    static func managedBlock(executableURL: URL) -> String {
        let executableDirectory = executableURL.deletingLastPathComponent().path
        let quotedDirectory = singleQuotedShellLiteral(executableDirectory)
        return """
        \(beginMarker)
        export PATH=\(quotedDirectory):"$PATH"
        export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
        \(endMarker)
        """
    }

    private func managedRange(in contents: String) throws -> Range<String.Index>? {
        let begin = contents.range(of: Self.beginMarker)
        let end = contents.range(of: Self.endMarker)

        if (begin == nil) != (end == nil) {
            throw ShellIntegrationError.malformedManagedBlock
        }
        guard let begin, let end, begin.lowerBound < end.lowerBound else {
            if begin == nil && end == nil { return nil }
            throw ShellIntegrationError.malformedManagedBlock
        }

        var upper = end.upperBound
        if upper < contents.endIndex, contents[upper] == "\n" {
            upper = contents.index(after: upper)
        }
        return begin.lowerBound..<upper
    }

    private func write(_ contents: String, to url: URL) throws {
        let existed = fileManager.fileExists(atPath: url.path)
        let attributes = existed ? try? fileManager.attributesOfItem(atPath: url.path) : nil
        let permissions = attributes?[.posixPermissions]

        try Data(contents.utf8).write(to: url, options: .atomic)
        if let permissions {
            try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private static func appending(block: String, to contents: String) -> String {
        guard !contents.isEmpty else { return block + "\n" }
        let separator = contents.hasSuffix("\n\n") ? "" : (contents.hasSuffix("\n") ? "\n" : "\n\n")
        return contents + separator + block + "\n"
    }

    private static func normalizeAfterRemoval(_ contents: String) -> String {
        var result = contents.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        while result.hasSuffix("\n\n\n") {
            result.removeLast()
        }
        return result
    }

    private static func singleQuotedShellLiteral(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
