import XCTest
@testable import ControllerKeys

final class ScriptOutputGateTests: XCTestCase {
	func testSuspensionCancelsOldCallbacksEvenAfterResume() {
		let gate = ScriptOutputGate()
		let oldGeneration = gate.currentGeneration
		XCTAssertTrue(gate.permits(oldGeneration))
		gate.setEnabled(false)
		XCTAssertFalse(gate.permits(oldGeneration))
		gate.setEnabled(true)
		XCTAssertFalse(gate.permits(oldGeneration))
		XCTAssertTrue(gate.permits(gate.currentGeneration))
	}
}
