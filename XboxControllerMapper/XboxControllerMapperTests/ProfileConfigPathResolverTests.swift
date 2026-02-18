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
        XCTAssertEqual(paths.legacyConfigURL, overrideDirectory.appendingPathComponent("config.json"))
    }

    func testResolveUsesDefaultControllerKeysAndLegacyPathsWithoutOverride() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths = ProfileConfigPathResolver.resolve(
            fileManager: .default,
            configDirectoryOverride: nil
        )

        XCTAssertEqual(paths.configDirectory, home.appendingPathComponent(".controllerkeys", isDirectory: true))
        XCTAssertEqual(paths.configURL, home.appendingPathComponent(".controllerkeys/config.json"))
        XCTAssertEqual(paths.legacyConfigURL, home.appendingPathComponent(".xbox-controller-mapper/config.json"))
    }
}
