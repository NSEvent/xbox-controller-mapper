import XCTest
@testable import TriggerKitCore
@testable import TriggerKitLibrary

final class AutomationMacroStoreTests: XCTestCase {
	func testStorePersistsAndReloadsMacros() throws {
		let url = temporaryFileURL()
		let store = AutomationMacroStore(fileURL: url, notificationCenter: NotificationCenter(), distributedNotificationCenter: nil)
		let macro = store.create(
			name: "Open Site",
			program: AutomationProgram(name: "Open Site", steps: [.openURL(OpenURLStep(url: "kevin.md"))])
		)
		store.flush()

		let reloaded = AutomationMacroStore(fileURL: url, notificationCenter: NotificationCenter(), distributedNotificationCenter: nil)

		XCTAssertEqual(reloaded.all().map(\.id), [macro.id])
		XCTAssertEqual(reloaded.macro(id: macro.id)?.program.steps, [.openURL(OpenURLStep(url: "https://kevin.md"))])
	}

	func testDuplicateCreatesNewIDAndCopyName() {
		let store = AutomationMacroStore(fileURL: temporaryFileURL(), notificationCenter: NotificationCenter(), distributedNotificationCenter: nil)
		let original = store.create(
			name: "Paste",
			program: AutomationProgram(name: "Paste", steps: [.typeText(TypeTextStep(text: "hello"))])
		)

		let copy = store.duplicate(id: original.id)

		XCTAssertNotNil(copy)
		XCTAssertNotEqual(copy?.id, original.id)
		XCTAssertEqual(copy?.name, "Paste Copy")
		XCTAssertEqual(copy?.program.name, "Paste Copy")
		XCTAssertEqual(copy?.program.steps, original.program.steps)
	}

	func testLegacyMigrationPreservesIDsAndKeepsExistingByDefault() throws {
		let legacyURL = temporaryFileURL()
		let sharedURL = temporaryFileURL()
		let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
		let legacy = AutomationMacro(
			id: id,
			name: "Legacy",
			program: AutomationProgram(name: "Legacy", steps: [.delay(DelayStep(seconds: 1))])
		)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		try encoder.encode([legacy]).write(to: legacyURL)

		let store = AutomationMacroStore(fileURL: sharedURL, notificationCenter: NotificationCenter(), distributedNotificationCenter: nil)
		XCTAssertEqual(store.migrateFromLegacyFile(at: legacyURL), 1)
		XCTAssertEqual(store.macro(id: id)?.name, "Legacy")

		let changed = AutomationMacro(
			id: id,
			name: "Changed",
			program: AutomationProgram(name: "Changed", steps: [.delay(DelayStep(seconds: 2))])
		)
		try encoder.encode([changed]).write(to: legacyURL)
		XCTAssertEqual(store.migrateFromLegacyFile(at: legacyURL), 0)
		XCTAssertEqual(store.macro(id: id)?.name, "Legacy")
	}

	func testImportCanReplaceExistingMacro() {
		let store = AutomationMacroStore(fileURL: temporaryFileURL(), notificationCenter: NotificationCenter(), distributedNotificationCenter: nil)
		let original = store.create(
			name: "Original",
			program: AutomationProgram(name: "Original", steps: [.delay(DelayStep(seconds: 1))])
		)
		let replacement = AutomationMacro(
			id: original.id,
			name: "Replacement",
			program: AutomationProgram(name: "Replacement", steps: [.delay(DelayStep(seconds: 2))])
		)

		XCTAssertEqual(store.importMacros([replacement], strategy: .replaceExisting), 1)
		XCTAssertEqual(store.macro(id: original.id)?.name, "Replacement")
	}

	private func temporaryFileURL() -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("triggerkit-tests", isDirectory: true)
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
			.appendingPathComponent("\(UUID().uuidString).json")
	}
}
