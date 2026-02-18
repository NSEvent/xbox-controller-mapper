import Foundation

struct ProfileConfigLoadSource: Equatable {
    let url: URL
    let migratingFromLegacy: Bool
}

enum ProfileConfigLoadSourceResolver {
    static func resolve(fileManager: FileManager, configURL: URL, legacyConfigURL: URL) -> ProfileConfigLoadSource? {
        if fileManager.fileExists(atPath: configURL.path) {
            return ProfileConfigLoadSource(url: configURL, migratingFromLegacy: false)
        }

        if fileManager.fileExists(atPath: legacyConfigURL.path) {
            return ProfileConfigLoadSource(url: legacyConfigURL, migratingFromLegacy: true)
        }

        return nil
    }
}
