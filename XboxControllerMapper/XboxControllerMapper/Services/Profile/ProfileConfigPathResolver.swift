import Foundation

struct ProfileConfigPaths: Equatable {
    let configDirectory: URL
    let configURL: URL
    let legacyConfigURL: URL
}

enum ProfileConfigPathResolver {
    static func resolve(fileManager: FileManager, configDirectoryOverride: URL?) -> ProfileConfigPaths {
        if let configDirectoryOverride {
            let configURL = configDirectoryOverride.appendingPathComponent("config.json")
            return ProfileConfigPaths(
                configDirectory: configDirectoryOverride,
                configURL: configURL,
                legacyConfigURL: configURL
            )
        }

        let home = fileManager.homeDirectoryForCurrentUser
        let configDirectory = home.appendingPathComponent(".controllerkeys", isDirectory: true)
        let configURL = configDirectory.appendingPathComponent("config.json")
        let legacyConfigDirectory = home.appendingPathComponent(".xbox-controller-mapper", isDirectory: true)
        let legacyConfigURL = legacyConfigDirectory.appendingPathComponent("config.json")
        return ProfileConfigPaths(
            configDirectory: configDirectory,
            configURL: configURL,
            legacyConfigURL: legacyConfigURL
        )
    }
}
