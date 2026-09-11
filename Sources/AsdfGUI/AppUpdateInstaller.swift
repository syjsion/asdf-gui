import CryptoKit
import Foundation

struct PreparedAppUpdate: Equatable, Sendable {
    let update: AvailableAppUpdate
    let stagedAppURL: URL
    let targetAppURL: URL
    let workingDirectory: URL
    let downloadedDMGURL: URL
}

enum AppUpdateInstallError: LocalizedError, Equatable {
    case missingDownloadAsset
    case untrustedDownloadURL
    case missingDigest
    case invalidDigest
    case httpStatus(Int)
    case checksumMismatch(expected: String, actual: String)
    case unsupportedInstallLocation
    case installationDirectoryNotWritable(String)
    case commandFailed(command: String, status: Int32, message: String)
    case mountedAppMissing
    case bundleIdentifierMismatch
    case versionMismatch(expected: String, actual: String?)
    case helperLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingDownloadAsset:
            return "This release does not contain a downloadable macOS DMG for this architecture."
        case .untrustedDownloadURL:
            return "The update asset is not hosted by the official syjsion/asdf-gui GitHub Release."
        case .missingDigest:
            return "The update asset does not include a SHA-256 digest, so it cannot be installed safely in-app."
        case .invalidDigest:
            return "The update asset contains an invalid SHA-256 digest."
        case .httpStatus(let status):
            return "The update download failed with HTTP status \(status)."
        case .checksumMismatch(let expected, let actual):
            return "The downloaded update failed SHA-256 verification. Expected \(expected), got \(actual)."
        case .unsupportedInstallLocation:
            return "In-app installation is unavailable from this app location. Move asdf GUI to a writable Applications folder, open it there, and try again."
        case .installationDirectoryNotWritable(let path):
            return "asdf GUI cannot replace the app in \(path). Move it to a location your user can write to and try again."
        case .commandFailed(let command, let status, let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(command) failed with exit status \(status)."
                : "\(command) failed with exit status \(status): \(detail)"
        case .mountedAppMissing:
            return "The downloaded DMG does not contain the expected asdf GUI app bundle."
        case .bundleIdentifierMismatch:
            return "The downloaded app has an unexpected bundle identifier and was not installed."
        case .versionMismatch(let expected, let actual):
            return "The downloaded app version does not match \(expected) (found \(actual ?? "unknown"))."
        case .helperLaunchFailed(let message):
            return "The update was prepared, but the installer could not start: \(message)"
        }
    }
}

enum AppUpdateSecurity {
    static let repositoryAssetPathPrefix = "/syjsion/asdf-gui/releases/download/"

    static func trustedReleaseAssetURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == "github.com"
            && url.path.hasPrefix(repositoryAssetPathPrefix)
    }

    static func normalizedSHA256(_ digest: String?) -> String? {
        guard var value = digest?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else { return nil }
        if value.hasPrefix("sha256:") {
            value.removeFirst("sha256:".count)
        }
        let hexadecimal = CharacterSet(charactersIn: "0123456789abcdef")
        guard value.count == 64,
              value.unicodeScalars.allSatisfy({ hexadecimal.contains($0) }) else { return nil }
        return value
    }

    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            guard let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct AppUpdateInstaller {
    private let session: URLSession
    private let commandRunner = AsdfCommandRunner()
    private let expectedBundleIdentifier = "io.github.syjsion.asdf-gui"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func prepare(
        update: AvailableAppUpdate,
        currentAppURL: URL = Bundle.main.bundleURL,
        architecture: MacArchitecture = .current
    ) async throws -> PreparedAppUpdate {
        try validateCurrentAppLocation(currentAppURL)

        guard let downloadURL = update.downloadURL,
              let assetName = update.assetName else {
            throw AppUpdateInstallError.missingDownloadAsset
        }
        guard AppUpdateSecurity.trustedReleaseAssetURL(downloadURL),
              downloadURL.lastPathComponent == assetName,
              assetName.lowercased().contains(architecture.releaseAssetToken),
              assetName.lowercased().hasSuffix(".dmg") else {
            throw AppUpdateInstallError.untrustedDownloadURL
        }
        guard update.digest != nil else {
            throw AppUpdateInstallError.missingDigest
        }
        guard let expectedSHA256 = AppUpdateSecurity.normalizedSHA256(update.digest) else {
            throw AppUpdateInstallError.invalidDigest
        }

        let workingDirectory = try makeWorkingDirectory(version: update.version)
        let dmgURL = workingDirectory.appendingPathComponent(assetName, isDirectory: false)

        var request = URLRequest(url: downloadURL)
        request.setValue("asdf-gui/\(AppBuildInfo.version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw AppUpdateInstallError.httpStatus(http.statusCode)
        }

        try FileManager.default.copyItem(at: temporaryURL, to: dmgURL)
        let actualSHA256 = try AppUpdateSecurity.sha256Hex(ofFileAt: dmgURL)
        guard actualSHA256 == expectedSHA256 else {
            throw AppUpdateInstallError.checksumMismatch(expected: expectedSHA256, actual: actualSHA256)
        }

        try await runRequired(
            executable: "/usr/bin/hdiutil",
            arguments: ["verify", dmgURL.path],
            displayName: "hdiutil verify"
        )

        let mountPoint = try await attachDiskImage(dmgURL)
        do {
            let mountedApp = try findMountedApp(at: mountPoint)
            try validateMountedApp(mountedApp, update: update)
            try await runRequired(
                executable: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", mountedApp.path],
                displayName: "codesign verify"
            )

            let stagedApp = workingDirectory.appendingPathComponent("asdf GUI.app", isDirectory: true)
            if FileManager.default.fileExists(atPath: stagedApp.path) {
                try FileManager.default.removeItem(at: stagedApp)
            }
            try FileManager.default.copyItem(at: mountedApp, to: stagedApp)
            try validateMountedApp(stagedApp, update: update)

            _ = try? await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", mountPoint.path]
            )

            return PreparedAppUpdate(
                update: update,
                stagedAppURL: stagedApp,
                targetAppURL: currentAppURL.standardizedFileURL,
                workingDirectory: workingDirectory,
                downloadedDMGURL: dmgURL
            )
        } catch {
            _ = try? await commandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["detach", mountPoint.path]
            )
            throw error
        }
    }

    func launchReplacementHelper(
        for prepared: PreparedAppUpdate,
        currentProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        let scriptURL = prepared.workingDirectory.appendingPathComponent("install-update.sh", isDirectory: false)
        do {
            try Self.replacementHelperScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptURL.path, String(currentProcessIdentifier), prepared.stagedAppURL.path, prepared.targetAppURL.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            throw AppUpdateInstallError.helperLaunchFailed(error.localizedDescription)
        }
    }

    private func validateCurrentAppLocation(_ currentAppURL: URL) throws {
        let appURL = currentAppURL.standardizedFileURL
        guard appURL.pathExtension.lowercased() == "app",
              !appURL.path.contains("/AppTranslocation/") else {
            throw AppUpdateInstallError.unsupportedInstallLocation
        }
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw AppUpdateInstallError.installationDirectoryNotWritable(parent.path)
        }
    }

    private func makeWorkingDirectory(version: String) throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = caches
            .appendingPathComponent(expectedBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let safeVersion = version
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let working = root.appendingPathComponent("\(safeVersion)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        return working
    }

    private func attachDiskImage(_ dmgURL: URL) async throws -> URL {
        let result = try await commandRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
            arguments: ["attach", "-readonly", "-nobrowse", "-plist", dmgURL.path]
        )
        guard result.exitCode == 0 else {
            throw AppUpdateInstallError.commandFailed(command: "hdiutil attach", status: result.exitCode, message: result.stderr)
        }

        let data = Data(result.stdout.utf8)
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let entities = root["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).last else {
            throw AppUpdateInstallError.commandFailed(command: "hdiutil attach", status: result.exitCode, message: "No mount point was returned.")
        }
        return URL(fileURLWithPath: mountPath, isDirectory: true)
    }

    private func findMountedApp(at mountPoint: URL) throws -> URL {
        let expected = mountPoint.appendingPathComponent("asdf GUI.app", isDirectory: true)
        if FileManager.default.fileExists(atPath: expected.path) {
            return expected
        }
        let contents = try FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        guard let app = contents.first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw AppUpdateInstallError.mountedAppMissing
        }
        return app
    }

    private func validateMountedApp(_ appURL: URL, update: AvailableAppUpdate) throws {
        guard let bundle = Bundle(url: appURL), bundle.bundleIdentifier == expectedBundleIdentifier else {
            throw AppUpdateInstallError.bundleIdentifierMismatch
        }
        let actualVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let expected = SemanticVersion(update.version),
              let actualVersion,
              SemanticVersion(actualVersion) == expected else {
            throw AppUpdateInstallError.versionMismatch(expected: update.version, actual: actualVersion)
        }
    }

    private func runRequired(executable: String, arguments: [String], displayName: String) async throws {
        let result = try await commandRunner.run(executable: URL(fileURLWithPath: executable), arguments: arguments)
        guard result.exitCode == 0 else {
            throw AppUpdateInstallError.commandFailed(
                command: displayName,
                status: result.exitCode,
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
    }

    static let replacementHelperScript = """
    #!/bin/sh
    set -u

    PID="$1"
    STAGED="$2"
    TARGET="$3"
    BACKUP="${TARGET}.asdf-gui-update-backup-$$"

    while /bin/kill -0 "$PID" >/dev/null 2>&1; do
      /bin/sleep 0.2
    done

    relaunch_target() {
      if [ -d "$TARGET" ]; then
        /usr/bin/open "$TARGET" >/dev/null 2>&1 || true
      fi
    }

    if [ ! -d "$STAGED" ] || [ ! -d "$TARGET" ]; then
      relaunch_target
      exit 70
    fi

    if ! /bin/mv "$TARGET" "$BACKUP"; then
      relaunch_target
      exit 73
    fi

    if /usr/bin/ditto "$STAGED" "$TARGET"; then
      /bin/rm -rf "$BACKUP" "$STAGED"
      /usr/bin/open "$TARGET" >/dev/null 2>&1 || true
      exit 0
    fi

    /bin/rm -rf "$TARGET"
    if /bin/mv "$BACKUP" "$TARGET"; then
      relaunch_target
    fi
    exit 74
    """
}
