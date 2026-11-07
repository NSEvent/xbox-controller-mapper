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

	func testBackupsInTheSameSecondAreAllKept() throws {
		let config = directory.appendingPathComponent("config.json")
		let service = ConfigBackupService()
		for version in 1...3 {
			try Data("{\"version\":\(version)}".utf8).write(to: config)
			service.createBackupIfNeeded(for: config)
		}

		let backups = try FileManager.default.contentsOfDirectory(
			at: directory.appendingPathComponent("backups"), includingPropertiesForKeys: nil)
		let contents = try Set(backups.map { try String(contentsOf: $0, encoding: .utf8) })
		XCTAssertEqual(contents, ["{\"version\":1}", "{\"version\":2}", "{\"version\":3}"])
	}
}
