import Foundation

struct ProfileConfigPaths: Equatable {
    let configDirectory: URL
    let configURL: URL
    let legacyConfigURLs: [URL]
}

enum ProfileConfigPathResolver {
    static func resolve(fileManager: FileManager, configDirectoryOverride: URL?) -> ProfileConfigPaths {
        if let configDirectoryOverride {
            let configURL = configDirectoryOverride.appendingPathComponent("config.json")
            return ProfileConfigPaths(
                configDirectory: configDirectoryOverride,
                configURL: configURL,
		legacyConfigURLs: [configURL]
            )
        }

        let home = fileManager.homeDirectoryForCurrentUser
	let configDirectory = home
	    .appendingPathComponent(".config", isDirectory: true)
	    .appendingPathComponent("controllerkeys", isDirectory: true)
        let configURL = configDirectory.appendingPathComponent("config.json")
	let previousConfigURL = home
	    .appendingPathComponent(".controllerkeys", isDirectory: true)
	    .appendingPathComponent("config.json")
	let legacyConfigURL = home
	    .appendingPathComponent(".xbox-controller-mapper", isDirectory: true)
	    .appendingPathComponent("config.json")
        return ProfileConfigPaths(
            configDirectory: configDirectory,
            configURL: configURL,
	    legacyConfigURLs: [previousConfigURL, legacyConfigURL]
        )
    }
}
