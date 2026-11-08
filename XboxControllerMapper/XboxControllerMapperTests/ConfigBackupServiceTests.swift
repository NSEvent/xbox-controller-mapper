import XCTest
@testable import ControllerKeys

final class ConfigBackupServiceTests: XCTestCase {
	private var directory: URL!

	override func setUpWithError() throws {
		try super.setUpWithError()
		directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("ConfigBackupServiceTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
	}

	override func tearDownWithError() throws {
		try? FileManager.default.removeItem(at: directory)
		try super.tearDownWithError()
	}

	private func backupContents() throws -> Set<String> {
		let backups = try FileManager.default.contentsOfDirectory(
			at: directory.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
		return try Set(backups.map { try String(contentsOf: $0, encoding: .utf8) })
	}

	func testBurstOfSavesKeepsOlderBackups() throws {
		let config = directory.appendingPathComponent("config.json")
		let service = ConfigBackupService()
		try Data("{\"version\":0}".utf8).write(to: config)
		service.createBackupIfNeeded(for: config)

		// A slider drag: many saves, each preceded by a backup attempt.
		for version in 1...10 {
			try Data("{\"version\":\(version)}".utf8).write(to: config)
			service.createBackupIfNeeded(for: config)
		}

		XCTAssertEqual(try backupContents(), ["{\"version\":0}"], "a burst must not push the pre-burst backup out of the ring")
	}

	func testBackupIsTakenOnceTheIntervalHasPassed() throws {
		let config = directory.appendingPathComponent("config.json")
		let service = ConfigBackupService()
		try Data("{\"version\":1}".utf8).write(to: config)
		service.createBackupIfNeeded(for: config)
		try Data("{\"version\":2}".utf8).write(to: config)
		service.createBackupIfNeeded(for: config, now: Date().addingTimeInterval(61))

		XCTAssertEqual(try backupContents(), ["{\"version\":1}", "{\"version\":2}"])
	}
}
