import CryptoKit
import Foundation

enum AsdfInstallationStatus: Hashable {
    case running
    case succeeded
    case failed
    case cancelled
}

struct AsdfInstallationTaskState: Identifiable {
    let id: UUID
    var status: AsdfInstallationStatus
    var version: String?
    var destination: URL?
    var log: String
    var errorMessage: String?

    var isRunning: Bool { status == .running }
}

enum AsdfInstallerError: LocalizedError {
    case invalidResponse
    case unsupportedArchitecture
    case releaseHasNoMatchingAsset(String)
    case missingSHA256Digest
    case checksumMismatch(expected: String, actual: String)
    case archiveMissingExecutable
    case installedExecutableFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The official asdf release service returned an invalid response."
        case .unsupportedArchitecture:
            return "This Mac architecture is not supported by the automatic asdf installer."
        case .releaseHasNoMatchingAsset(let name):
            return "The latest asdf release does not contain the expected macOS asset: \(name)."
        case .missingSHA256Digest:
            return "The official asdf release asset does not publish a SHA-256 digest, so automatic installation was stopped."
        case .checksumMismatch(let expected, let actual):
            return "The downloaded asdf archive failed SHA-256 verification. Expected \(expected), got \(actual)."
        case .archiveMissingExecutable:
            return "The downloaded asdf archive did not contain a regular executable named asdf."
        case .installedExecutableFailed(let message):
            return message.isEmpty ? "The installed asdf executable could not be verified." : message
        }
    }
}

struct AsdfGitHubRelease: Decodable, Hashable {
    struct Asset: Decodable, Hashable {
        let name: String
        let browserDownloadURL: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    let tagName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

enum AsdfReleaseResolver {
    static func releaseArchitecture() throws -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "amd64"
        #else
        throw AsdfInstallerError.unsupportedArchitecture
        #endif
    }

    static func assetName(version: String, architecture: String) -> String {
        "asdf-v\(version)-darwin-\(architecture).tar.gz"
    }

    static func asset(in release: AsdfGitHubRelease, architecture: String) throws -> AsdfGitHubRelease.Asset {
        let expectedName = assetName(version: release.version, architecture: architecture)
        guard let asset = release.assets.first(where: { $0.name == expectedName }) else {
            throw AsdfInstallerError.releaseHasNoMatchingAsset(expectedName)
        }
        return asset
    }

    static func sha256(from digest: String?) throws -> String {
        guard let digest, digest.hasPrefix("sha256:") else {
            throw AsdfInstallerError.missingSHA256Digest
        }
        let value = String(digest.dropFirst("sha256:".count)).lowercased()
        guard value.count == 64, value.allSatisfy({ $0.isHexDigit }) else {
            throw AsdfInstallerError.missingSHA256Digest
        }
        return value
    }
}

struct AsdfInstaller {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/asdf-vm/asdf/releases/latest")!

    private let session: URLSession
    private let fileManager: FileManager
    private let runner: AsdfCommandRunner

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        runner: AsdfCommandRunner = AsdfCommandRunner()
    ) {
        self.session = session
        self.fileManager = fileManager
        self.runner = runner
    }

    func defaultDestinationURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/asdf", isDirectory: false)
    }

    func installLatest(onOutput: @escaping @Sendable (String) -> Void = { _ in }) async throws -> URL {
        onOutput("Checking the latest official asdf release…\n")
        let release = try await fetchLatestRelease()
        let architecture = try AsdfReleaseResolver.releaseArchitecture()
        let asset = try AsdfReleaseResolver.asset(in: release, architecture: architecture)
        let expectedDigest = try AsdfReleaseResolver.sha256(from: asset.digest)

        onOutput("Latest stable release: \(release.tagName)\n")
        onOutput("Downloading \(asset.name)…\n")

        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("asdf-gui-install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let archiveURL = temporaryRoot.appendingPathComponent(asset.name)
        let downloadedURL = try await download(asset.browserDownloadURL)
        try fileManager.moveItem(at: downloadedURL, to: archiveURL)

        onOutput("Verifying SHA-256…\n")
        let actualDigest = try sha256(of: archiveURL)
        guard actualDigest == expectedDigest else {
            throw AsdfInstallerError.checksumMismatch(expected: expectedDigest, actual: actualDigest)
        }
        onOutput("✓ SHA-256 verified\n")

        let extractionURL = temporaryRoot.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        onOutput("Extracting official archive…\n")
        let extractResult = try await runner.run(
            executable: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", archiveURL.path, "-C", extractionURL.path]
        )
        guard extractResult.exitCode == 0 else {
            throw AsdfInstallerError.installedExecutableFailed(extractResult.stderr)
        }

        let extractedExecutable = try findExecutable(in: extractionURL)
        let destination = defaultDestinationURL()
        let destinationDirectory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let staged = destinationDirectory.appendingPathComponent(".asdf-gui-install-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: staged) }
        try fileManager.copyItem(at: extractedExecutable, to: staged)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)

        onOutput("Verifying downloaded executable…\n")
        let stagedResult = try await runner.run(executable: staged, arguments: ["version"])
        guard stagedResult.exitCode == 0 else {
            throw AsdfInstallerError.installedExecutableFailed(stagedResult.stderr)
        }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)

        let installedResult = try await runner.run(executable: destination, arguments: ["version"])
        guard installedResult.exitCode == 0 else {
            throw AsdfInstallerError.installedExecutableFailed(installedResult.stderr)
        }

        onOutput("✓ Installed asdf \(release.tagName) at \(destination.path)\n")
        return destination
    }

    private func fetchLatestRelease() async throws -> AsdfGitHubRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("asdf-gui", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(AsdfGitHubRelease.self, from: data)
    }

    private func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("asdf-gui", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response)
        return temporaryURL
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AsdfInstallerError.invalidResponse
        }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 128 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func findExecutable(in directory: URL) throws -> URL {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw AsdfInstallerError.archiveMissingExecutable
        }

        for case let url as URL in enumerator where url.lastPathComponent == "asdf" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true, values.isSymbolicLink != true {
                return url
            }
        }
        throw AsdfInstallerError.archiveMissingExecutable
    }
}
