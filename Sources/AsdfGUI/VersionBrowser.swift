import Foundation

struct ToolVersionRecord: Identifiable, Hashable {
    let version: String
    let isInstalled: Bool
    let isLatest: Bool

    var id: String { version }
}

enum VersionCatalog {
    static func records(
        available: [String],
        installed: [String],
        latest: String?
    ) -> [ToolVersionRecord] {
        let installedSet = Set(installed)
        var seen = Set<String>()
        var ordered: [String] = []

        for version in available + installed where seen.insert(version).inserted {
            ordered.append(version)
        }

        return ordered.map { version in
            ToolVersionRecord(
                version: version,
                isInstalled: installedSet.contains(version),
                isLatest: version == latest
            )
        }
    }
}
