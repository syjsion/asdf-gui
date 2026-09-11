import Foundation
import Observation

struct SemanticVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let core = trimmed.split(separator: "-", maxSplits: 1).first.map(String.init) ?? trimmed
        let parts = core.split(separator: ".").map(String.init)
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else { return nil }
        let patch = parts.count > 2 ? Int(parts[2]) : 0
        guard let patch else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

enum MacArchitecture: String, Sendable {
    case arm64
    case x86_64

    static var current: MacArchitecture {
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }

    var releaseAssetToken: String {
        switch self {
        case .arm64: "macos-arm64"
        case .x86_64: "macos-x86_64"
        }
    }
}

struct AppReleaseAsset: Decodable, Equatable, Sendable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
        case size
    }
}

struct AppRelease: Decodable, Equatable, Sendable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [AppReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    var semanticVersion: SemanticVersion? { SemanticVersion(tagName) }
}

struct AvailableAppUpdate: Equatable, Sendable {
    let version: String
    let prerelease: Bool
    let releaseURL: URL
    let assetName: String?
    let downloadURL: URL?
    let digest: String?
    let downloadSize: Int?
}

enum AppUpdateResolution: Equatable, Sendable {
    case upToDate(latestVersion: String?)
    case updateAvailable(AvailableAppUpdate)
}

enum AppUpdateResolver {
    static func resolve(
        currentVersion: String,
        releases: [AppRelease],
        architecture: MacArchitecture
    ) -> AppUpdateResolution {
        let published = releases.filter { !$0.draft && $0.semanticVersion != nil }
        guard let latest = published.max(by: { lhs, rhs in
            (lhs.semanticVersion ?? SemanticVersion("0.0.0")!) < (rhs.semanticVersion ?? SemanticVersion("0.0.0")!)
        }) else {
            return .upToDate(latestVersion: nil)
        }

        guard let latestVersion = latest.semanticVersion else {
            return .upToDate(latestVersion: latest.tagName)
        }
        let current = SemanticVersion(currentVersion) ?? SemanticVersion("0.0.0")!
        guard current < latestVersion else {
            return .upToDate(latestVersion: latest.tagName)
        }

        let matchingAsset = latest.assets.first { asset in
            let lowercased = asset.name.lowercased()
            return lowercased.contains(architecture.releaseAssetToken) && lowercased.hasSuffix(".dmg")
        }

        return .updateAvailable(
            AvailableAppUpdate(
                version: latest.tagName,
                prerelease: latest.prerelease,
                releaseURL: latest.htmlURL,
                assetName: matchingAsset?.name,
                downloadURL: matchingAsset?.browserDownloadURL,
                digest: matchingAsset?.digest,
                downloadSize: matchingAsset?.size
            )
        )
    }
}

enum AppUpdateError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid update response."
        case .httpStatus(let status):
            return "GitHub update check failed with HTTP status \(status)."
        }
    }
}

struct AppUpdateChecker {
    private let session: URLSession
    private let releasesURL = URL(string: "https://api.github.com/repos/syjsion/asdf-gui/releases?per_page=20")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(
        currentVersion: String,
        architecture: MacArchitecture = .current
    ) async throws -> AppUpdateResolution {
        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("asdf-gui/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw AppUpdateError.httpStatus(http.statusCode)
        }

        let releases = try JSONDecoder().decode([AppRelease].self, from: data)
        return AppUpdateResolver.resolve(
            currentVersion: currentVersion,
            releases: releases,
            architecture: architecture
        )
    }
}

enum AppBuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0-dev"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }
}

enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate(latestVersion: String?)
    case updateAvailable(AvailableAppUpdate)
    case downloading(AvailableAppUpdate)
    case readyToInstall(PreparedAppUpdate)
    case installing(String)
    case failed(String)
}

@MainActor
@Observable
final class AppUpdateModel {
    var state: AppUpdateState = .idle
    private(set) var availableUpdate: AvailableAppUpdate?

    private let checker: AppUpdateChecker
    private let installer: AppUpdateInstaller

    init(
        checker: AppUpdateChecker = AppUpdateChecker(),
        installer: AppUpdateInstaller = AppUpdateInstaller()
    ) {
        self.checker = checker
        self.installer = installer
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing:
            true
        case .idle, .upToDate, .updateAvailable, .readyToInstall, .failed:
            false
        }
    }

    var isChecking: Bool { state == .checking }

    func check() async {
        guard !isBusy else { return }
        state = .checking
        do {
            switch try await checker.check(currentVersion: AppBuildInfo.version) {
            case .upToDate(let latestVersion):
                availableUpdate = nil
                state = .upToDate(latestVersion: latestVersion)
            case .updateAvailable(let update):
                availableUpdate = update
                state = .updateAvailable(update)
            }
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func downloadAndPrepare() async {
        guard !isBusy, let update = availableUpdate else { return }
        state = .downloading(update)
        do {
            let prepared = try await installer.prepare(update: update)
            state = .readyToInstall(prepared)
        } catch is CancellationError {
            state = .updateAvailable(update)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func beginInstallation() throws {
        guard case .readyToInstall(let prepared) = state else { return }
        do {
            try installer.launchReplacementHelper(for: prepared)
            state = .installing(prepared.update.version)
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }
}
