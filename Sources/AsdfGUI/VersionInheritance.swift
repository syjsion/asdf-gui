import Foundation

enum ParentToolVersionsLocator {
    static func nearestParentFile(from directory: URL, fileName: String = ".tool-versions") -> URL? {
        let fm = FileManager.default
        var candidate = directory.standardizedFileURL.deletingLastPathComponent()

        while true {
            let file = candidate.appendingPathComponent(fileName)
            if fm.fileExists(atPath: file.path) {
                return file
            }

            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                return nil
            }
            candidate = parent
        }
    }
}
