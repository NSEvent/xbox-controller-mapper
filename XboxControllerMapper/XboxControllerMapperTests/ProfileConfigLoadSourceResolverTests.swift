import XCTest
@testable import ControllerKeys

final class ProfileConfigLoadSourceResolverTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = .default
        tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "controllerkeys-load-source-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? fileManager.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        fileManager = nil
        try super.tearDownWithError()
    }

    func testResolveReturnsNilWhenNoConfigFilesExist() {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let legacyURL = tempDirectory.appendingPathComponent("legacy-config.json")

        let source = ProfileConfigLoadSourceResolver.resolve(
            fileManager: fileManager,
            configURL: configURL,
            legacyConfigURL: legacyURL
        )

        XCTAssertNil(source)
    }

    func testResolvePrefersCurrentConfigWhenBothFilesExist() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let legacyURL = tempDirectory.appendingPathComponent("legacy-config.json")
        try Data("{}".utf8).write(to: configURL)
        try Data("{}".utf8).write(to: legacyURL)

        let source = ProfileConfigLoadSourceResolver.resolve(
            fileManager: fileManager,
            configURL: configURL,
            legacyConfigURL: legacyURL
        )

        XCTAssertEqual(
            source,
            ProfileConfigLoadSource(url: configURL, migratingFromLegacy: false)
        )
    }

    func testResolveFallsBackToLegacyConfigWhenCurrentMissing() throws {
        let configURL = tempDirectory.appendingPathComponent("config.json")
        let legacyURL = tempDirectory.appendingPathComponent("legacy-config.json")
        try Data("{}".utf8).write(to: legacyURL)

        let source = ProfileConfigLoadSourceResolver.resolve(
            fileManager: fileManager,
            configURL: configURL,
            legacyConfigURL: legacyURL
        )

        XCTAssertEqual(
            source,
            ProfileConfigLoadSource(url: legacyURL, migratingFromLegacy: true)
        )
    }
}
