import XCTest
@testable import ControllerKeys

final class MixedSequenceRecognitionTests: XCTestCase {
	private func mapping(_ steps: [Set<ControllerButton>], timeout: TimeInterval = 0.5) -> SequenceMapping {
		SequenceMapping(chordSteps: steps.map(SequenceStep.init), stepTimeout: timeout, keyCode: 99)
	}
	private func detector(_ mappings: [SequenceMapping]) -> ReleasedSequenceDetector {
		let detector = ReleasedSequenceDetector()
		detector.chordWindow = 0.1
		detector.configure(mappings)
		return detector
	}
	@discardableResult private func tap(_ buttons: Set<ControllerButton>, at time: TimeInterval, into detector: ReleasedSequenceDetector) -> [SequenceMapping] {
		XCTAssertTrue(detector.receive(buttons, at: time).isEmpty)
		return detector.receive([], at: time + 0.01)
	}

	func testSingleChordSingleCompletesOnlyOnFinalRelease() {
		let sequence = mapping([[.a], [.b, .x], [.y]])
		let detector = detector([sequence])
		tap([.a], at: 0, into: detector)
		_ = detector.receive([.x], at: 0.1)
		_ = detector.receive([.x, .b], at: 0.15)
		_ = detector.receive([.b], at: 0.17)
		XCTAssertTrue(detector.receive([], at: 0.2).isEmpty)
		XCTAssertTrue(detector.receive([.y], at: 0.3).isEmpty)
		XCTAssertEqual(detector.receive([], at: 0.4).map(\.id), [sequence.id])
		XCTAssertTrue(detector.receive([], at: 0.5).isEmpty)
	}

	func testRepeatedChordsAndReversedMemberOrder() {
		let sequence = mapping([[.a, .b], [.a, .b]])
		let detector = detector([sequence])
		tap([.a, .b], at: 0, into: detector)
		_ = detector.receive([.b], at: 0.1)
		_ = detector.receive([.a, .b], at: 0.15)
		XCTAssertEqual(detector.receive([], at: 0.2).map(\.id), [sequence.id])
	}

	func testTimeoutStartsAtReleaseAndStopsAtNextFirstPress() {
		let sequence = mapping([[.a, .b], [.x]], timeout: 0.5)
		let detector = detector([sequence])
		_ = detector.receive([.a, .b], at: 0)
		detector.expire(at: 10)
		_ = detector.receive([], at: 10)
		_ = detector.receive([.x], at: 10.5)
		detector.expire(at: 100)
		XCTAssertEqual(detector.receive([], at: 100).map(\.id), [sequence.id])
	}

	func testTimeoutJustBeyondBoundaryDoesNotComplete() {
		let detector = detector([mapping([[.a, .b], [.x]], timeout: 0.5)])
		tap([.a, .b], at: 0, into: detector)
		XCTAssertTrue(tap([.x], at: 0.511, into: detector).isEmpty)
		XCTAssertEqual(detector.feedback, .timedOut)
	}

	func testLateAdditionsAndRolloverRequireRetry() {
		for late in [false, true] {
			let detector = detector([mapping([[.a, .b], [.x]])])
			_ = detector.receive([.a], at: 0)
			if late { _ = detector.receive([.a, .b], at: 0.101) }
			else { _ = detector.receive([.b], at: 0.05) }
			XCTAssertEqual(detector.feedback, .ambiguous)
			_ = detector.receive([], at: 0.15)
			XCTAssertTrue(tap([.x], at: 0.2, into: detector).isEmpty)
		}
	}

	func testHoldingMemberAcrossStepsCannotComplete() {
		let detector = detector([mapping([[.a, .b], [.a, .x]])])
		_ = detector.receive([.a, .b], at: 0)
		_ = detector.receive([.a], at: 0.05)
		_ = detector.receive([.a, .x], at: 0.07)
		XCTAssertTrue(detector.receive([], at: 0.09).isEmpty)
		XCTAssertEqual(detector.feedback, .ambiguous)
	}

	func testWrongStepCanRestartAndExtraButtonsDoNotMatch() {
		let sequence = mapping([[.a, .b], [.x]])
		let detector = detector([sequence])
		tap([.a, .b], at: 0, into: detector)
		tap([.a, .b, .y], at: 0.1, into: detector)
		XCTAssertTrue(tap([.x], at: 0.2, into: detector).isEmpty)
		tap([.a, .b], at: 0.3, into: detector)
		tap([.a, .b], at: 0.4, into: detector)
		XCTAssertEqual(tap([.x], at: 0.5, into: detector).map(\.id), [sequence.id])
	}

	func testSharedPrefixesAndMultipleCompletionsRemainAdditive() {
		let short = mapping([[.a, .b], [.x]])
		let same = mapping([[.a, .b], [.x]])
		let long = mapping([[.a, .b], [.x], [.y]])
		let detector = detector([short, same, long])
		tap([.a, .b], at: 0, into: detector)
		XCTAssertEqual(tap([.x], at: 0.1, into: detector).map(\.id), [short.id, same.id])
		XCTAssertEqual(tap([.y], at: 0.2, into: detector).map(\.id), [long.id])
	}

	func testResetDiscardsProgressAndWaitsForHeldControls() {
		let detector = detector([mapping([[.a, .b], [.x]])])
		tap([.a, .b], at: 0, into: detector)
		detector.reset(initiallyHeld: [.a])
		_ = detector.receive([.a, .b], at: 0.1)
		_ = detector.receive([], at: 0.2)
		XCTAssertTrue(tap([.x], at: 0.3, into: detector).isEmpty)
	}

	func testRecordingUsesTheSameBoundariesAsRecognition() {
		var recording = SequenceRecording(initiallyHeld: [.y], chordWindow: 0.1)
		let events: [(Set<ControllerButton>, Double)] = [([.y, .a], 0), ([], 0.1), ([.a], 0.2), ([.a, .b], 0.25), ([.b], 0.26), ([], 0.3), ([.x], 0.4), ([], 0.5)]
		for (buttons, time) in events { recording.receive(buttons, at: time) }
		XCTAssertEqual(recording.steps, [SequenceStep([.a, .b]), SequenceStep([.x])])
		XCTAssertTrue(recording.canUse)
		let sequence = SequenceMapping(chordSteps: recording.steps)
		let detector = detector([sequence])
		detector.reset(initiallyHeld: [.y])
		var matches: [SequenceMapping] = []
		for (buttons, time) in events { matches += detector.receive(buttons, at: time) }
		XCTAssertEqual(matches.map(\.id), [sequence.id])
	}

	func testRecordingAmbiguityRetryUndoAndLimit() {
		var recording = SequenceRecording(initiallyHeld: [], chordWindow: 0.1, limit: 2)
		recording.receive([.a], at: 0); recording.receive([], at: 0.01)
		recording.receive([.a], at: 0.1); recording.receive([.a, .b], at: 0.3)
		XCTAssertTrue(recording.ambiguous)
		recording.retryStep() // Still held: wait until neutral.
		recording.receive([], at: 0.4)
		recording.receive([.b, .x], at: 0.5)
		XCTAssertFalse(recording.canUse)
		recording.receive([], at: 0.6)
		XCTAssertTrue(recording.canUse)
		recording.receive([.y], at: 0.7); recording.receive([], at: 0.8)
		XCTAssertEqual(recording.steps.count, 2)
		recording.undo(); XCTAssertEqual(recording.steps, [SequenceStep([.a])])
	}
}
