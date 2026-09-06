import XCTest
@testable import ControllerKeys

final class ControllerInputMuteGateTests: XCTestCase {
	func testMutedPressCannotBecomeAnActiveRelease() {
		var gate = ControllerInputMuteGate()
		gate.setEnabled(false, pendingButtons: [])
		XCTAssertEqual(gate.decision(for: .buttonPressed(.a), generation: gate.generation), .ignore)
		gate.setEnabled(true, pendingButtons: [])
		XCTAssertEqual(gate.decision(for: .buttonReleased(.a, holdDuration: 0.2), generation: gate.generation), .cancelRelease)
		XCTAssertEqual(gate.decision(for: .buttonPressed(.a), generation: gate.generation), .forward)
	}

	func testQueuedInputFromBeforePauseCannotReplayAfterResume() {
		var gate = ControllerInputMuteGate()
		let oldGeneration = gate.generation
		gate.setEnabled(false, pendingButtons: [])
		gate.setEnabled(true, pendingButtons: [])
		XCTAssertEqual(gate.decision(for: .buttonPressed(.a), generation: oldGeneration), .ignore)
		XCTAssertEqual(gate.decision(for: .buttonReleased(.a, holdDuration: 0.2), generation: oldGeneration), .cancelRelease)
		XCTAssertEqual(gate.decision(for: .buttonPressed(.a), generation: gate.generation), .forward)
	}

	func testPendingChordWindowRemainsMutedUntilRelease() {
		var gate = ControllerInputMuteGate()
		gate.setEnabled(false, pendingButtons: [])
		gate.setEnabled(true, pendingButtons: [.a])
		XCTAssertEqual(gate.decision(for: .buttonPressed(.a), generation: gate.generation), .ignore)
		XCTAssertEqual(gate.decision(for: .buttonReleased(.a, holdDuration: 0.2), generation: gate.generation), .cancelRelease)
		XCTAssertEqual(gate.decision(for: .buttonPressed(.a), generation: gate.generation), .forward)
	}

	func testPartiallyMutedChordCannotBecomeAnotherAction() {
		var gate = ControllerInputMuteGate()
		gate.setEnabled(false, pendingButtons: [])
		gate.setEnabled(true, pendingButtons: [.a])
		XCTAssertEqual(gate.decision(for: .chordDetected([.a, .b]), generation: gate.generation), .ignore)
		for button in [ControllerButton.a, .b] {
			XCTAssertEqual(gate.decision(for: .buttonReleased(button, holdDuration: 0.2), generation: gate.generation), .cancelRelease)
			XCTAssertEqual(gate.decision(for: .buttonPressed(button), generation: gate.generation), .forward)
		}
	}

	func testDisconnectClearsMuteWithoutReplayingStaleQueuedInput() {
		var gate = ControllerInputMuteGate()
		gate.setEnabled(false, pendingButtons: [.a])
		gate.setEnabled(true, pendingButtons: [.a])
		let oldGeneration = gate.generation
		gate.resetForDisconnect()
		XCTAssertEqual(gate.decision(for: .buttonPressed(.a), generation: oldGeneration), .ignore)
		XCTAssertEqual(gate.decision(for: .buttonPressed(.a), generation: gate.generation), .forward)
	}

	func testRepeatedEnableDoesNotInvalidateCurrentInput() {
		var gate = ControllerInputMuteGate()
		let generation = gate.generation
		gate.setEnabled(true, pendingButtons: [.a])
		XCTAssertEqual(gate.decision(for: .buttonPressed(.a), generation: generation), .forward)
		XCTAssertEqual(gate.decision(for: .buttonReleased(.a, holdDuration: 0.2), generation: generation), .forward)
	}
}
