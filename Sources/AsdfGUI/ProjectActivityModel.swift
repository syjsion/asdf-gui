import Foundation
import Observation

@MainActor
@Observable
final class ProjectActivityModel {
    private(set) var favoritePaths: Set<String>
    private(set) var lastUsedDates: [String: Date]

    private let preferences: PreferencesStore

    init(preferences: PreferencesStore = PreferencesStore()) {
        self.preferences = preferences
        self.favoritePaths = preferences.favoriteProjectPaths()
        self.lastUsedDates = preferences.projectLastUsedDates()
    }

    func isFavorite(_ project: ManagedProject) -> Bool {
        favoritePaths.contains(project.path)
    }

    func toggleFavorite(_ project: ManagedProject) {
        if favoritePaths.contains(project.path) {
            favoritePaths.remove(project.path)
        } else {
            favoritePaths.insert(project.path)
        }
        preferences.setFavoriteProjectPaths(favoritePaths)
    }

    func markUsed(_ project: ManagedProject, at date: Date = Date()) {
        lastUsedDates[project.path] = date
        preferences.setProjectLastUsedDates(lastUsedDates)
    }

    func remove(_ project: ManagedProject) {
        favoritePaths.remove(project.path)
        lastUsedDates.removeValue(forKey: project.path)
        preferences.setFavoriteProjectPaths(favoritePaths)
        preferences.setProjectLastUsedDates(lastUsedDates)
    }

    func prune(to projects: [ManagedProject]) {
        let paths = Set(projects.map(\.path))
        let favorites = favoritePaths.intersection(paths)
        let recent = lastUsedDates.filter { paths.contains($0.key) }
        guard favorites != favoritePaths || recent != lastUsedDates else { return }
        favoritePaths = favorites
        lastUsedDates = recent
        preferences.setFavoriteProjectPaths(favorites)
        preferences.setProjectLastUsedDates(recent)
    }
}
