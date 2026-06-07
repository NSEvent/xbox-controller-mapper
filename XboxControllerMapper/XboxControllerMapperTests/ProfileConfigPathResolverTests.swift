import XCTest
@testable import ControllerKeys

final class ProfileConfigPathResolverTests: XCTestCase {
    func testResolveUsesOverrideDirectoryForBothConfigAndLegacyPaths() {
        let overrideDirectory = URL(fileURLWithPath: "/tmp/controllerkeys-tests")
        let paths = ProfileConfigPathResolver.resolve(
            fileManager: .default,
            configDirectoryOverride: overrideDirectory
        )

        XCTAssertEqual(paths.configDirectory, overrideDirectory)
        XCTAssertEqual(paths.configURL, overrideDirectory.appendingPathComponent("config.json"))
	XCTAssertEqual(paths.legacyConfigURLs, [overrideDirectory.appendingPathComponent("config.json")])
    }

    func testResolveUsesDefaultControllerKeysAndLegacyPathsWithoutOverride() {
        let home = FileManager.default.homeDirectoryForCurrentUser
	let configDirectory = home
	    .appendingPathComponent(".config", isDirectory: true)
	    .appendingPathComponent("controllerkeys", isDirectory: true)
        let paths = ProfileConfigPathResolver.resolve(
            fileManager: .default,
            configDirectoryOverride: nil
        )

	XCTAssertEqual(paths.configDirectory, configDirectory)
	XCTAssertEqual(paths.configURL, configDirectory.appendingPathComponent("config.json"))
	XCTAssertEqual(paths.legacyConfigURLs, [
	    home.appendingPathComponent(".controllerkeys/config.json"),
	    home.appendingPathComponent(".xbox-controller-mapper/config.json")
	])
    }
}
