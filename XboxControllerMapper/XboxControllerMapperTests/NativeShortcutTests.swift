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
}
