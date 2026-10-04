import AppKit
import XCTest
@testable import ControllerKeys

private actor RecordingShortcutRunner: ShortcutProcessRunning {
	var calls: [[String]] = []
	let failure: Bool
	init(failure: Bool = false) { self.failure = failure }
	func run(arguments: [String], timeout: TimeInterval) async throws -> String {
		calls.append(arguments)
		try await Task.sleep(for: .milliseconds(50))
		if failure { throw ShortcutExecutionError.failed("Permission denied") }
		return arguments == ["list"] ? "Beta\nAlpha\nAlpha\n" : ""
	}
}

@MainActor
final class NativeShortcutTests: XCTestCase {
	func testListsSortedInstalledNames() async {
		let runner = RecordingShortcutRunner()
		let service = NativeShortcutService(runner: runner)
		await service.refresh()
		XCTAssertEqual(service.names, ["Alpha", "Beta"])
	}
	func testNamesArePassedAsLiteralArgumentsAndFailureIsNotRetried() async {
		let runner = RecordingShortcutRunner(failure: true)
		let service = NativeShortcutService(runner: runner)
		let name = "Quotes ' \" $(touch nope); spaces"
		let success = await service.run(name: name)
		XCTAssertFalse(success)
		let calls = await runner.calls
		XCTAssertEqual(calls, [["run", "--", name]])
		XCTAssertEqual(service.status, "Permission denied")
		XCTAssertEqual(service.lastRunSucceeded, false)
	}
	func testRepeatedPressDoesNotStartConcurrentRun() async {
		let runner = RecordingShortcutRunner()
		let service = NativeShortcutService(runner: runner)
		let first = Task { await service.run(name: "Alpha") }
		while !service.isRunning { await Task.yield() }
		let second = await service.run(name: "Beta")
		XCTAssertFalse(second)
		let success = await first.value
		XCTAssertTrue(success)
		XCTAssertEqual(service.lastRunSucceeded, true)
		XCTAssertFalse(service.isRunning)
		let calls = await runner.calls
		XCTAssertEqual(calls, [["run", "--", "Alpha"]])
	}
	func testShortcutRoundTripAndEditorState() throws {
		let command = SystemCommand.runShortcut(name: "My Workflow")
		let decoded = try JSONDecoder().decode(SystemCommand.self, from: JSONEncoder().encode(command))
		XCTAssertEqual(decoded, command)
		var state = MappingEditorState()
		state.loadSystemCommand(decoded)
		XCTAssertEqual(state.buildSystemCommand(), command)
		XCTAssertEqual(command.category, .shortcut)
	}

	func testProductionProcessRunnerTimesOutOwnedProcess() async {
		let runner = NativeShortcutProcessRunner(executableURL: URL(fileURLWithPath: "/bin/sleep"))
		let started = Date()
		do {
			_ = try await runner.run(arguments: ["5"], timeout: 0.05)
			XCTFail("Expected timeout")
		} catch { XCTAssertTrue(error is ShortcutExecutionError) }
		XCTAssertLessThan(Date().timeIntervalSince(started), 2.5)
	}

	func testProductionRunnerPassesShellTextLiterally() async throws {
		let runner = NativeShortcutProcessRunner(executableURL: URL(fileURLWithPath: "/usr/bin/printf"))
		let name = "-leading 'quote' $(touch nope); spaces"
		let output = try await runner.run(arguments: ["%s", name], timeout: 2)
		XCTAssertEqual(output, name)
	}
	func testImportedShortcutNeedsItemizedReview() {
		let profile = Profile(name: "External", buttonMappings: [.a: KeyMapping(systemCommand: .runShortcut(name: "Workflow"))])
		let report = ProfileImportSafetyAuditor.audit(profile)
		XCTAssertTrue(report.requiresUserConfirmation)
		XCTAssertEqual(report.shortcuts.map(\.name), ["Workflow"])
		XCTAssertEqual(report.shortcuts.map(\.context), ["Button A"])
	}

	func testLiveClipboardFixtureThroughProductionRunnerAndCommandExecutor() async throws {
		guard let name = ProcessInfo.processInfo.environment["CONTROLLERKEYS_SHORTCUT_FIXTURE"], name.hasPrefix("ControllerKeys QA ") else {
			throw XCTSkip("Opt in with an owned Text → Copy to Clipboard → Nothing QA shortcut")
		}
		let expected = "ControllerKeys native Shortcuts integration passed 01a10068"
		let clipboard = NSPasteboard.general
		func snapshot() throws -> [[NSPasteboard.PasteboardType: Data]] {
			try (clipboard.pasteboardItems ?? []).map { item in
				try Dictionary(uniqueKeysWithValues: item.types.map { type in
					(type, try XCTUnwrap(item.data(forType: type), "Cannot preserve a clipboard type"))
				})
			}
		}
		let saved = try snapshot()
		defer {
			clipboard.clearContents()
			let items = saved.map { values in
				let item = NSPasteboardItem()
				for (type, data) in values { item.setData(data, forType: type) }
				return item
			}
			if !items.isEmpty { clipboard.writeObjects(items) }
			XCTAssertTrue((try? snapshot()) == saved, "Original clipboard types and data restored")
		}
		let runner = NativeShortcutProcessRunner()
		_ = try await runner.run(arguments: ["run", "--", name], timeout: 60)
		XCTAssertTrue(clipboard.string(forType: .string) == expected, "Production runner delivered the QA message")
		let service = NativeShortcutService.shared
		await service.refresh()
		XCTAssertTrue(service.names.contains(name))
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("controllerkeys-shortcut-qa-\(UUID())")
		let profiles = ProfileManager(configDirectoryOverride: folder)
		defer { try? FileManager.default.removeItem(at: folder) }
		let executor = SystemCommandExecutor(profileManager: profiles)
		let finished = expectation(description: "Mapped Shortcut command completed")
		executor.webhookFeedbackHandler = { success, message in
			XCTAssertTrue(success, message)
			XCTAssertEqual(message, "Finished \(name).")
			XCTAssertTrue(clipboard.string(forType: .string) == expected, "Mapped command delivered the QA message")
			finished.fulfill()
		}
		clipboard.clearContents(); clipboard.setString("ControllerKeys QA waiting for mapped action", forType: .string)
		executor.execute(.runShortcut(name: name))
		await fulfillment(of: [finished], timeout: 65)
	}
}
