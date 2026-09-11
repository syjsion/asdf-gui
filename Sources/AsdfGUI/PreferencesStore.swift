import Foundation

extension Notification.Name {
    static let asdfGUIProjectActivityDidChange = Notification.Name("asdfGUIProjectActivityDidChange")
}

struct PreferencesStore {
    private enum Key {
        static let asdfExecutablePath = "asdfExecutablePath"
        static let projectPaths = "projectPaths"
        static let favoriteProjectPaths = "favoriteProjectPaths"
        static let projectLastUsedDates = "projectLastUsedDates"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func executableURL() -> URL? {
        guard let path = defaults.string(forKey: Key.asdfExecutablePath), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    func setExecutableURL(_ url: URL?) {
        if let url {
            defaults.set(url.standardizedFileURL.path, forKey: Key.asdfExecutablePath)
        } else {
            defaults.removeObject(forKey: Key.asdfExecutablePath)
        }
    }

    func projects() -> [ManagedProject] {
        let paths = defaults.stringArray(forKey: Key.projectPaths) ?? []
        return paths.map { ManagedProject(path: $0) }
    }

    func setProjects(_ projects: [ManagedProject]) {
        defaults.set(projects.map(\.path), forKey: Key.projectPaths)
    }

    func favoriteProjectPaths() -> Set<String> {
        Set(defaults.stringArray(forKey: Key.favoriteProjectPaths) ?? [])
    }

    func setFavoriteProjectPaths(_ paths: Set<String>) {
        defaults.set(paths.sorted(), forKey: Key.favoriteProjectPaths)
        NotificationCenter.default.post(name: .asdfGUIProjectActivityDidChange, object: nil)
    }

    func projectLastUsedDates() -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: Key.projectLastUsedDates) else { return [:] }
        var result: [String: Date] = [:]
        for (path, value) in raw {
            if let timestamp = value as? Double {
                result[path] = Date(timeIntervalSince1970: timestamp)
            } else if let number = value as? NSNumber {
                result[path] = Date(timeIntervalSince1970: number.doubleValue)
            }
        }
        return result
    }

    func setProjectLastUsedDates(_ dates: [String: Date]) {
        let raw = dates.mapValues(\.timeIntervalSince1970)
        defaults.set(raw, forKey: Key.projectLastUsedDates)
        NotificationCenter.default.post(name: .asdfGUIProjectActivityDidChange, object: nil)
    }
}
