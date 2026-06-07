import Foundation

struct ProfileConfigLoadSource: Equatable {
    let url: URL
    let migratingFromLegacy: Bool
}

enum ProfileConfigLoadSourceResolver {
    static func resolve(fileManager: FileManager, configURL: URL, legacyConfigURLs: [URL]) -> ProfileConfigLoadSource? {
        if fileManager.fileExists(atPath: configURL.path) {
            return ProfileConfigLoadSource(url: configURL, migratingFromLegacy: false)
        }

	if let legacyConfigURL = legacyConfigURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return ProfileConfigLoadSource(url: legacyConfigURL, migratingFromLegacy: true)
        }

        return nil
    }
}
