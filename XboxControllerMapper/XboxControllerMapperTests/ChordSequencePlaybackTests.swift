import XCTest
@testable import ControllerKeys

/// Exercise actual press/release ingress, chord buffering, preview capture,
/// persistence, and action dispatch. Only the output simulator is mocked.
@MainActor
final class ChordSequencePlaybackTests: MappingEngineTestCase {
	private func install(_ steps: [[ControllerButton]], ordinaryChords: [ChordMapping] = []) -> SequenceMapping {
		let sequence = SequenceMapping(chordSteps: steps.map { SequenceStep(Set($0)) }, stepTimeout: 2, keyCode: 99)
		profileManager.setActiveProfile(Profile(name: "Chord sequence playback", buttonMappings: [:],
			chordMappings: ordinaryChords, sequenceMappings: [sequence]))
		return sequence
	}

	private func count(_ key: CGKeyCode = 99) -> Int {
		mockInputSimulator.events.filter {
			if case .pressKey(let code, _) = $0 { return code == key }
			return false
		}.count
	}

	/// Physical snapshots enqueue on main, then on the engine queue. Drain both
	/// before negative assertions so a delayed action cannot make a test pass.
	private func drainInput() async {
		let queue = mappingEngine.inputQueue
		await withCheckedContinuation { continuation in
			DispatchQueue.main.async {
				queue.async { continuation.resume() }
			}
		}
	}

	private func press(_ buttons: [ControllerButton], source: ControllerPreviewLayout? = nil) async {
		for button in buttons { controllerService.buttonPressed(button, source: source) }
		// Also allow the ordinary chord handler's 50 ms buffer to resolve.
		await waitForTasks(0.08)
		await drainInput()
	}

	private func release(_ buttons: [ControllerButton], source: ControllerPreviewLayout? = nil) async {
		for button in buttons { controllerService.buttonReleased(button, source: source) }
		await drainInput()
	}

	private func step(_ buttons: [ControllerButton], source: ControllerPreviewLayout? = nil) async {
		await press(buttons, source: source)
		await release(Array(buttons.reversed()), source: source)
	}

	func testThreeDistinctChordsFireOnlyOnFinalFullReleaseAndKeepOrdinaryActions() async {
		let steps: [[ControllerButton]] = [[.a, .b], [.x, .y], [.leftBumper, .rightBumper]]
		_ = install(steps, ordinaryChords: [
			ChordMapping(buttons: Set(steps[0]), keyCode: 40),
			ChordMapping(buttons: Set(steps[1]), keyCode: 41),
			ChordMapping(buttons: Set(steps[2]), keyCode: 42)
		])
		await step([.b, .a]) // Member order within a chord does not matter.
		XCTAssertEqual(count(), 0)
		XCTAssertEqual(count(40), 1)
		await step([.y, .x])
		XCTAssertEqual(count(), 0)
		XCTAssertEqual(count(41), 1)
		await press(steps[2])
		XCTAssertEqual(count(42), 1)
		XCTAssertEqual(count(), 0, "Pressing the final chord is not completion")
		await release([.leftBumper])
		XCTAssertEqual(count(), 0, "Every member of the final chord must release")
		await release([.rightBumper])
		XCTAssertEqual(count(), 1)
		await release(steps[2])
		XCTAssertEqual(count(), 1, "Duplicate release notifications must not repeat the action")
		for buttons in steps { await step(buttons) }
		XCTAssertEqual(count(), 2, "A second complete performance should trigger once more")
	}

	func testChordThenSingleThenThreeButtonChord() async {
		_ = install([[.a, .b], [.x], [.y, .leftBumper, .rightBumper]])
		await step([.b, .a])
		XCTAssertEqual(count(), 0)
		await step([.x])
		XCTAssertEqual(count(), 0)
		await press([.rightBumper, .y, .leftBumper])
		await release([.y, .rightBumper])
		XCTAssertEqual(count(), 0)
		await release([.leftBumper])
		XCTAssertEqual(count(), 1)
	}

	func testSingleThenChordThenSameSingleButton() async {
		_ = install([[.a], [.b, .x], [.a]])
		await step([.a])
		await step([.x, .b])
		XCTAssertEqual(count(), 0)
		await press([.a])
		controllerService.buttonPressed(.a) // A held-state repeat is not a step.
		await drainInput()
		XCTAssertEqual(count(), 0)
		await release([.a])
		XCTAssertEqual(count(), 1)
	}

	func testRepeatedChordsAndRepeatedSingleStepsRequireRepressing() async {
		_ = install([[.a, .b], [.a, .b], [.x], [.x], [.a, .b]])
		await press([.a, .b])
		controllerService.buttonPressed(.a); controllerService.buttonPressed(.b)
		await drainInput()
		await release([.b, .a])
		await step([.x]); await step([.x]); await step([.a, .b])
		XCTAssertEqual(count(), 0, "Repeating held notifications cannot replace the second chord")
		// The last chord also starts a fresh attempt. Finish the remaining steps.
		await step([.b, .a]); await step([.x]); await step([.x]); await step([.a, .b])
		XCTAssertEqual(count(), 1)
	}

	func testSeparateTapsCannotStandInForAChordInAMixedSequence() async {
		_ = install([[.a, .b], [.x], [.y, .rightBumper]])
		await step([.a]); await step([.b])
		await step([.x]); await step([.y, .rightBumper])
		XCTAssertEqual(count(), 0, "Non-overlapping A then B is not A+B")
		await step([.a, .b]); await step([.x]); await step([.rightBumper, .y])
		XCTAssertEqual(count(), 1)
	}

	func testWrongChordExtraMemberAndWrongStepOrderDoNotTrigger() async {
		let expected: [[ControllerButton]] = [[.a, .b], [.x], [.y, .rightBumper]]
		_ = install(expected)
		for attempt: [[ControllerButton]] in [
			[[.a, .b], [.x], [.y, .leftBumper]],
			[[.a, .b], [.x], [.y, .rightBumper, .leftBumper]],
			[[.a, .b], [.y, .rightBumper], [.x]]
		] {
			for buttons in attempt { await step(buttons) }
			XCTAssertEqual(count(), 0, "Only exact chord membership in the configured step order can complete")
		}
		for buttons in expected { await step(buttons) }
		XCTAssertEqual(count(), 1, "Rejected attempts must not poison the next correct attempt")
	}

	func testCarryingAHeldMemberIntoNextChordIsRejectedThenRecovers() async {
		_ = install([[.a, .b], [.a, .x], [.y]])
		await press([.a, .b])
		await release([.b]) // A is carried across, so there is no step boundary.
		await press([.x])
		await release([.a, .x])
		await step([.y])
		XCTAssertEqual(count(), 0)
		await step([.a, .b]); await step([.a, .x]); await step([.y])
		XCTAssertEqual(count(), 1)
	}

	func testRecordedPedalChordSingleChordSurvivesSaveReloadAndActuallyRuns() async throws {
		controllerService.isConnected = true
		profileManager.bindControllerPreview(to: controllerService)
		profileManager.setActiveProfile(Profile(name: "Recorded pedals", buttonMappings: [:]))
		let session = SequenceInputSession()
		defer { session.cancel() }
		session.startRecording(controller: controllerService, engine: mappingEngine)
		let performed: [[ControllerButton]] = [
			[.footPedalRight, .footPedalLeft], [.footPedalMiddle], [.footPedalMiddle, .footPedalRight]
		]
		for buttons in performed { await step(buttons, source: .footPedal) }
		let recording = try XCTUnwrap(session.acceptRecording())
		XCTAssertEqual(recording, performed.map { SequenceStep(Set($0)) })
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
		let saved = SequenceMapping(chordSteps: recording, stepTimeout: 2, keyCode: 99)
		profileManager.addSequence(saved)
		profileManager.flushPendingSaves()
		session.cancel()
		XCTAssertEqual(mappingEngine.inputPreviewCount, 0)
		let reloaded = ProfileManager(configDirectoryOverride: testConfigDirectory)
		let profile = try XCTUnwrap(reloaded.activeProfile)
		XCTAssertEqual(profile.sequenceMappings, [saved])
		profileManager.setActiveProfile(profile)
		await step([.footPedalLeft, .footPedalRight], source: .footPedal)
		await step([.footPedalMiddle], source: .footPedal)
		XCTAssertEqual(count(), 0)
		await step([.footPedalRight, .footPedalMiddle], source: .footPedal)
		XCTAssertEqual(count(), 1)
	}

	func testTrySequenceMatchesConsecutiveChordsWithoutExecutingTheirActions() async {
		controllerService.isConnected = true
		let steps: [[ControllerButton]] = [[.a, .b], [.x, .y], [.leftBumper, .rightBumper]]
		let sequence = install(steps, ordinaryChords: steps.map { ChordMapping(buttons: Set($0), keyCode: 40) })
		let session = SequenceInputSession()
		defer { session.cancel() }
		session.startTrying(sequence, controller: controllerService, engine: mappingEngine)
		for (index, buttons) in steps.enumerated() {
			await step(buttons)
			XCTAssertEqual(session.matchedSteps, index + 1)
		}
		XCTAssertTrue(session.message.contains("Matched"))
		XCTAssertEqual(count(), 0)
		XCTAssertEqual(count(40), 0)
		session.cancel()
		for buttons in steps { await step(buttons) }
		XCTAssertEqual(count(), 1)
		XCTAssertEqual(count(40), 3)
	}

	func testSharedChordPrefixesAllowShortAndLongMixedSequencesToFinish() async {
		let short = install([[.a, .b], [.x]])
		let long = SequenceMapping(chordSteps: [SequenceStep([.a, .b]), SequenceStep([.x]), SequenceStep([.y, .rightBumper])],
			stepTimeout: 2, keyCode: 98)
		profileManager.addSequence(long)
		XCTAssertEqual(profileManager.activeProfile?.sequenceMappings.map(\.id), [short.id, long.id])
		await step([.a, .b]); await step([.x])
		XCTAssertEqual(count(99), 1)
		XCTAssertEqual(count(98), 0)
		await step([.rightBumper, .y])
		XCTAssertEqual(count(99), 1)
		XCTAssertEqual(count(98), 1)
	}
}
