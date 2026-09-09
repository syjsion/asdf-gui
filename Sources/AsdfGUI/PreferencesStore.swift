import Foundation

struct PreferencesStore {
    private enum Key {
        static let asdfExecutablePath = "asdfExecutablePath"
        static let projectPaths = "projectPaths"
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
}
