import XCTest
@testable import ControllerKeys

/// A script stuck in a loop must be stopped, not left holding the script
/// queue, and the engine must keep running scripts afterwards.
final class ScriptRunawayTerminationTests: XCTestCase {
	func testInfiniteLoopIsStoppedAndEngineRecovers() {
		let simulator = MockInputSimulator()
		let engine = ScriptEngine(inputSimulator: simulator, inputQueue: DispatchQueue(label: "test.runaway"),
								  terminationSeconds: 0.5)

		let finished = expectation(description: "runaway script returns")
		var loopResult: ScriptResult?
		DispatchQueue.global().async {
			loopResult = engine.execute(script: Script(name: "Spin", source: "while (true) {}"),
										trigger: ScriptTrigger(button: .a))
			finished.fulfill()
		}
		wait(for: [finished], timeout: 5)
		guard case .error(let message)? = loopResult else {
			return XCTFail("a stopped script must report an error, got \(String(describing: loopResult))")
		}
		XCTAssertTrue(message.contains("still running"), message)

		let next = engine.execute(script: Script(name: "After", source: "press(15);"),
								  trigger: ScriptTrigger(button: .a))
		if case .error(let message) = next { XCTFail("engine must recover: \(message)") }
		XCTAssertEqual(simulator.events.compactMap {
			if case .pressKey(let code, _) = $0 { return code }
			return nil
		}, [CGKeyCode(15)])
	}

	func testTimeBlockedInDelaysDoesNotCountTowardTheLimit() {
		let simulator = MockInputSimulator()
		let engine = ScriptEngine(inputSimulator: simulator, inputQueue: DispatchQueue(label: "test.delays"),
								  terminationSeconds: 0.5)
		// 1.2s of delay() against a 0.5s limit, then a loop that gives JSC a
		// chance to act on an expired limit.
		_ = engine.execute(script: Script(name: "Delays",
										  source: "delay(0.6); delay(0.6); for (var i = 0; i < 100000; i++) {} press(16);"),
						   trigger: ScriptTrigger(button: .a))
		XCTAssertEqual(simulator.events.count { if case .pressKey(16, _) = $0 { return true }; return false }, 1)
	}

	func testErrorAfterLongDelaysKeepsItsOwnMessage() {
		let engine = ScriptEngine(inputSimulator: MockInputSimulator(), inputQueue: DispatchQueue(label: "test.error"),
								  terminationSeconds: 0.5)
		let result = engine.execute(script: Script(name: "Throws", source: "delay(0.6); undefinedFunction();"),
									trigger: ScriptTrigger(button: .a))
		guard case .error(let message) = result else { return XCTFail("expected an error, got \(result)") }
		XCTAssertFalse(message.contains("still running"), message)
		XCTAssertTrue(message.contains("undefinedFunction"), message)
	}
}
