import XCTest
@testable import ControllerKeys

/// `shellAsync` callbacks run after their script returned. They must write to
/// their own script's state and stay behind the output gate the script ran under.
final class ScriptAsyncCallbackTests: XCTestCase {
	private var engine: ScriptEngine!
	private var simulator: MockInputSimulator!

	override func setUp() {
		super.setUp()
		simulator = MockInputSimulator()
		engine = ScriptEngine(inputSimulator: simulator, inputQueue: DispatchQueue(label: "test.scriptAsync"))
	}

	override func tearDown() {
		engine = nil
		simulator = nil
		super.tearDown()
	}

	private func run(_ script: Script) -> ScriptResult {
		engine.execute(script: script, trigger: ScriptTrigger(button: .a))
	}

	private func pressedKeys() -> [CGKeyCode] {
		simulator.events.compactMap {
			if case .pressKey(let code, _) = $0 { return code }
			return nil
		}
	}

	func testCallbackWritesItsOwnScriptState() async throws {
		var writer = Script(name: "Writer", source: """
		shellAsync("sleep 0.2; echo done", function(out) { state.set("result", out); });
		""")
		let other = Script(name: "Other", source: "state.set('unrelated', 1);")
		_ = run(writer)
		_ = run(other)
		try await Task.sleep(nanoseconds: 700_000_000)

		writer.source = "if (state.get('result') === 'done') press(12);"
		_ = run(writer)
		XCTAssertEqual(pressedKeys(), [12], "the callback's state.set must land in the script that called shellAsync")
	}

	func testCallbackFromBeforeOutputDisableCannotPress() async throws {
		let caller = Script(name: "Caller", source: """
		shellAsync("sleep 0.2", function() { press(13); });
		""")
		_ = run(caller)
		engine.outputGate.setEnabled(false)
		engine.outputGate.setEnabled(true)
		// A newer script reinstalls press() under the new gate generation.
		_ = run(Script(name: "Later", source: "log('later');"))
		try await Task.sleep(nanoseconds: 700_000_000)

		XCTAssertEqual(pressedKeys(), [], "output was disabled after the script ran, so its callback must stay silent")
	}

	func testCallbackStillPressesWhileGateUnchanged() async throws {
		_ = run(Script(name: "Caller", source: """
		shellAsync("sleep 0.1", function() { press(14); });
		"""))
		let pressed = await waitForCondition(timeout: 2) { self.pressedKeys() == [14] }
		XCTAssertTrue(pressed)
	}
	func testCallbackKeepsOriginalTriggerAfterAnotherScriptRuns() async {
		let caller = Script(name: "Original", source: "shellAsync('sleep 0.1', function() { if (trigger.button === 'a') press(15); });")
		_ = engine.execute(script: caller, trigger: ScriptTrigger(button: .a))
		_ = engine.execute(script: Script(name: "Later", source: "state.set('seen', true);"), trigger: ScriptTrigger(button: .b))
		let pressed = await waitForCondition(timeout: 2) { self.pressedKeys() == [15] }
		XCTAssertTrue(pressed)
	}

	func testCallbackCannotRepopulateStateOrEmitAfterProfileStateIsCleared() async throws {
		var script = Script(name: "Old profile", source: "shellAsync('sleep 0.1', function() { state.set('late', true); press(16); });")
		_ = run(script)
		engine.clearState()
		try await Task.sleep(nanoseconds: 500_000_000)
		script.source = "if (state.get('late')) press(17);"
		_ = run(script)
		XCTAssertEqual(pressedKeys(), [])
	}

}
