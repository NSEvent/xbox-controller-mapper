import XCTest
@testable import ControllerKeys

/// A config that fails to load must never be silently replaced. Bootstrap
/// creates an in-memory default profile so the app stays usable, but that
/// default must not be written over the user's file, and the original bytes
/// must survive any later user-initiated save.
@MainActor
final class ProfileConfigLoadFailureTests: XCTestCase {
	private var configDirectory: URL!
	private var configURL: URL!
	private let corruptBytes = Data("{\"profiles\": [ this is not valid json".utf8)

	override func setUp() async throws {
		try await super.setUp()
		configDirectory = FileManager.default.temporaryDirectory
			.appendingPathComponent("controllerkeys-load-failure-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
		configURL = configDirectory.appendingPathComponent("config.json")
		try corruptBytes.write(to: configURL)
	}

	override func tearDown() async throws {
		try? FileManager.default.removeItem(at: configDirectory)
		configDirectory = nil
		configURL = nil
		try await super.tearDown()
	}

	func testBootstrapDefaultDoesNotOverwriteUnreadableConfig() throws {
		let manager = ProfileManager(configDirectoryOverride: configDirectory)
		manager.flushPendingSaves()

		XCTAssertNotNil(manager.activeProfile, "app should stay usable with an in-memory default")
		XCTAssertNotNil(manager.configLoadError, "load failure must stay visible after bootstrap")
		XCTAssertEqual(try Data(contentsOf: configURL), corruptBytes)
	}

	func testUnreadableConfigIsPreservedBeforeFirstUserSave() throws {
		let manager = ProfileManager(configDirectoryOverride: configDirectory)
		manager.setMapping(KeyMapping(keyCode: 12), for: .a)
		manager.flushPendingSaves()

		let preserved = try FileManager.default.contentsOfDirectory(at: configDirectory, includingPropertiesForKeys: nil)
			.filter { $0.lastPathComponent.hasPrefix("config.json.load-failed-") }
		XCTAssertEqual(preserved.count, 1)
		XCTAssertEqual(try preserved.first.map { try Data(contentsOf: $0) }, corruptBytes)
	}

	func testFreshInstallPersistsBootstrapDefault() throws {
		try FileManager.default.removeItem(at: configURL)
		let manager = ProfileManager(configDirectoryOverride: configDirectory)
		manager.flushPendingSaves()

		XCTAssertNotNil(manager.activeProfile)
		XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path), "a fresh install should write its default config")
	}
}
