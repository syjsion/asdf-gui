import Foundation

enum ProjectSortOrder: String, CaseIterable, Identifiable, Sendable {
    case name
    case path
    case toolCount
    case recent

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .name: "Name"
        case .path: "Path"
        case .toolCount: "Tool count"
        case .recent: "Recently used"
        }
    }
}

enum ProjectListScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case favorites

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .all: "All Projects"
        case .favorites: "Favorites"
        }
    }
}

enum ProjectListPlanner {
    static func displayedSnapshots(
        _ snapshots: [ProjectSnapshot],
        searchText: String,
        scope: ProjectListScope,
        sortOrder: ProjectSortOrder,
        favoritePaths: Set<String>,
        lastUsedDates: [String: Date]
    ) -> [ProjectSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = snapshots.filter { snapshot in
            let matchesScope = scope == .all || favoritePaths.contains(snapshot.project.path)
            guard matchesScope else { return false }

            return query.isEmpty
                || snapshot.project.name.localizedCaseInsensitiveContains(query)
                || snapshot.project.path.localizedCaseInsensitiveContains(query)
                || snapshot.requirements.contains { $0.tool.localizedCaseInsensitiveContains(query) }
        }

        return filtered.sorted { lhs, rhs in
            let lhsFavorite = favoritePaths.contains(lhs.project.path)
            let rhsFavorite = favoritePaths.contains(rhs.project.path)
            if lhsFavorite != rhsFavorite {
                return lhsFavorite && !rhsFavorite
            }

            switch sortOrder {
            case .name:
                return compareName(lhs, rhs)
            case .path:
                let order = lhs.project.path.localizedCaseInsensitiveCompare(rhs.project.path)
                return order == .orderedSame ? compareName(lhs, rhs) : order == .orderedAscending
            case .toolCount:
                if lhs.requirements.count == rhs.requirements.count {
                    return compareName(lhs, rhs)
                }
                return lhs.requirements.count > rhs.requirements.count
            case .recent:
                let lhsDate = lastUsedDates[lhs.project.path]
                let rhsDate = lastUsedDates[rhs.project.path]
                switch (lhsDate, rhsDate) {
                case let (left?, right?) where left != right:
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return compareName(lhs, rhs)
                }
            }
        }
    }

    private static func compareName(_ lhs: ProjectSnapshot, _ rhs: ProjectSnapshot) -> Bool {
        lhs.project.name.localizedCaseInsensitiveCompare(rhs.project.name) == .orderedAscending
    }
}
