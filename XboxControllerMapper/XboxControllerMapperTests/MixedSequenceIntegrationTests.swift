import XCTest
@testable import ControllerKeys

@MainActor
final class MixedSequenceIntegrationTests: MappingEngineTestCase {
	private var sequence: SequenceMapping {
		SequenceMapping(chordSteps: [SequenceStep([.a, .b]), SequenceStep([.x])], stepTimeout: 1, keyCode: 99)
	}
	private func actionCount(_ key: CGKeyCode) -> Int {
		mockInputSimulator.events.filter { if case .pressKey(let code, _) = $0 { return code == key }; return false }.count
	}
	private func tap(_ buttons: [ControllerButton]) async {
		for button in buttons { controllerService.buttonPressed(button) }
		await waitForTasks(0.06)
		for button in buttons { controllerService.buttonReleased(button) }
		await waitForTasks(0.03)
	}

	func testRealPhysicalChordStillRunsOrdinaryActionAndCompletesSequenceOnce() async {
		profileManager.setActiveProfile(Profile(name: "Mixed", buttonMappings: [:],
			chordMappings: [ChordMapping(buttons: [.a, .b], keyCode: 31)], sequenceMappings: [sequence]))
		await tap([.b, .a])
		XCTAssertEqual(actionCount(31), 1)
		XCTAssertEqual(actionCount(99), 0)
		controllerService.buttonPressed(.x)
		await waitForTasks(0.1)
		XCTAssertEqual(actionCount(99), 0, "Final press is not completion")
		controllerService.buttonReleased(.x)
		await waitForTasks(0.15)
		XCTAssertEqual(actionCount(99), 1)
	}

	func testCanonicalControllerAutoFollowDoesNotResetMixedSequence() async {
		profileManager.bindControllerPreview(to: controllerService)
		let mixed = SequenceMapping(chordSteps: [SequenceStep([.a, .b]), SequenceStep([.footPedalMiddle])], stepTimeout: 1, keyCode: 99)
		profileManager.setActiveProfile(Profile(name: "Auto follow", buttonMappings: [:], sequenceMappings: [mixed]))
		await tap([.a, .b])
		controllerService.buttonPressed(.footPedalMiddle, source: .footPedal)
		controllerService.buttonReleased(.footPedalMiddle, source: .footPedal)
		await waitForTasks(0.15)
		XCTAssertEqual(profileManager.activeProfile?.controllerPreviewLayout, .footPedal)
		XCTAssertEqual(actionCount(99), 1)
	}

	func testProfileChangeAndPreviewClearPendingProgress() async {
		let profile = Profile(name: "First", buttonMappings: [:], sequenceMappings: [sequence])
		profileManager.setActiveProfile(profile)
		await tap([.a, .b])
		profileManager.setActiveProfile(Profile(name: "Second", buttonMappings: [:], sequenceMappings: [sequence]))
		await tap([.x])
		XCTAssertEqual(actionCount(99), 0)
		await tap([.a, .b])
		let lease = mappingEngine.beginInputPreview()
		mappingEngine.endInputPreview(lease)
		await tap([.x])
		XCTAssertEqual(actionCount(99), 0)
		await tap([.a, .b]); await tap([.x])
		XCTAssertEqual(actionCount(99), 1)
	}

	func testLegacyPhysicalSequenceStillCompletesWhileFirstButtonHeld() async {
		profileManager.setActiveProfile(Profile(name: "Legacy", buttonMappings: [:],
			sequenceMappings: [SequenceMapping(steps: [.a, .b], keyCode: 99)]))
		controllerService.buttonPressed(.a)
		await waitForTasks(0.1)
		controllerService.buttonPressed(.b)
		await waitForTasks(0.15)
		XCTAssertEqual(actionCount(99), 1)
		controllerService.buttonReleased(.a); controllerService.buttonReleased(.b)
	}

	func testRecordingCancelPreservesDraftAndAcceptanceReplacesOnlyExplicitly() async {
		controllerService.isConnected = true
		var draft = SequenceEditorDraft()
		draft.load(SequenceMapping(steps: [.y, .y]))
		let before = draft.steps
		let session = SequenceInputSession()
		defer { session.cancel() }
		session.startRecording(controller: controllerService, engine: mappingEngine)
		await tap([.a, .b]); await tap([.x])
		XCTAssertEqual(session.recording?.steps, sequence.inputSteps)
		XCTAssertEqual(draft.steps, before)
		session.cancel()
		XCTAssertEqual(draft.steps, before)
		XCTAssertEqual(mappingEngine.inputPreviewCount, 0)
		session.startRecording(controller: controllerService, engine: mappingEngine)
		await tap([.a, .b]); await tap([.x])
		if let recorded = session.acceptRecording() { draft.useRecording(recorded) }
		XCTAssertEqual(draft.steps, sequence.inputSteps)
		XCTAssertTrue(draft.usesReleaseSteps)
		XCTAssertGreaterThan(mappingEngine.inputPreviewCount, 0)
	}

	func testTrySequenceEmitsNoMappedActionsAndRestoresNormalMapping() async {
		controllerService.isConnected = true
		profileManager.setActiveProfile(Profile(name: "Try", buttonMappings: [.x: KeyMapping(keyCode: 4)],
			chordMappings: [ChordMapping(buttons: [.a, .b], keyCode: 31)], sequenceMappings: [sequence]))
		let session = SequenceInputSession()
		defer { session.cancel() }
		session.startTrying(sequence, controller: controllerService, engine: mappingEngine)
		await tap([.a, .b]); await tap([.x])
		XCTAssertEqual(session.matchedSteps, 2)
		XCTAssertTrue(session.message.contains("Matched"))
		XCTAssertEqual(actionCount(99), 0)
		XCTAssertEqual(actionCount(31), 0)
		XCTAssertEqual(actionCount(4), 0)
		session.cancel()
		await tap([.a, .b]); await tap([.x])
		XCTAssertEqual(actionCount(99), 1)
		XCTAssertEqual(actionCount(31), 1)
		XCTAssertGreaterThan(actionCount(4), 0)
	}

	func testRecordingUsesPhysicalTimestampsEvenWhenMainActorIsBusy() async {
		controllerService.isConnected = true
		let session = SequenceInputSession()
		defer { session.cancel() }
		session.startRecording(controller: controllerService, engine: mappingEngine)
		// Publish transitions off-main while deliberately holding main delivery.
		let controller = controllerService!
		DispatchQueue.global().sync {
			controller.buttonPressed(.a)
			Thread.sleep(forTimeInterval: 0.09)
			controller.buttonPressed(.b)
			controller.buttonReleased(.a); controller.buttonReleased(.b)
		}
		await waitForTasks(0.1)
		XCTAssertTrue(session.recording?.ambiguous == true, "Queued delivery must not turn late presses into a chord")
	}

	func testDisconnectInterruptsRecordingAndReleasesPreviewAfterNeutral() async {
		controllerService.isConnected = true
		let session = SequenceInputSession()
		defer { session.cancel() }
		session.startRecording(controller: controllerService, engine: mappingEngine)
		controllerService.buttonPressed(.a)
		await waitForTasks(0.03)
		controllerService.isConnected = false
		XCTAssertTrue(session.interrupted)
		XCTAssertNil(session.recording)
		controllerService.buttonReleased(.a)
		await waitForTasks(0.1)
		XCTAssertEqual(mappingEngine.inputPreviewCount, 0)
		XCTAssertEqual(actionCount(99), 0)
	}

	func testMixedSequenceSurvivesProfileManagerSaveReload() throws {
		let profile = Profile(name: "Saved mixed sequence", buttonMappings: [:], sequenceMappings: [sequence])
		profileManager.setActiveProfile(profile)
		profileManager.flushPendingSaves()
		let restored = ProfileManager(configDirectoryOverride: testConfigDirectory)
		XCTAssertEqual(restored.activeProfile?.sequenceMappings, profile.sequenceMappings)
	}
	func testMutedReleaseDoesNotMakeFirstFreshSequenceDisappear() async {
		profileManager.setActiveProfile(Profile(name: "Mute", buttonMappings: [:], sequenceMappings: [sequence]))
		controllerService.buttonPressed(.y)
		await waitForTasks(0.05)
		let lease = mappingEngine.beginInputPreview()
		controllerService.buttonReleased(.y)
		await waitForTasks(0.05)
		mappingEngine.endInputPreview(lease)
		await tap([.a, .b]); await tap([.x])
		XCTAssertEqual(actionCount(99), 1)
	}

	func testQueuedOldProfilePressCannotBecomeNewProfilesFirstStep() async {
		let profile = Profile(name: "Old", buttonMappings: [:], sequenceMappings: [sequence])
		profileManager.setActiveProfile(profile)
		controllerService.buttonPressed(.a) // Snapshot is queued but not yet delivered.
		profileManager.setActiveProfile(Profile(name: "New", buttonMappings: [:], sequenceMappings: [sequence]))
		controllerService.buttonPressed(.b)
		controllerService.buttonReleased(.a); controllerService.buttonReleased(.b)
		await waitForTasks(0.1)
		await tap([.x])
		XCTAssertEqual(actionCount(99), 0)
		await tap([.a, .b]); await tap([.x])
		XCTAssertEqual(actionCount(99), 1)
	}

	func testPeerRoutedButtonsCannotFireLocalMixedSequence() async {
		let relay = UniversalControlMouseRelay.shared
		relay.setDropsOutgoingMessagesForTesting(true)
		defer { relay.setRemoteSessionActive(false); relay.setDropsOutgoingMessagesForTesting(false) }
		profileManager.setActiveProfile(Profile(name: "Peer", buttonMappings: [:], sequenceMappings: [sequence]))
		relay.setRemoteSessionActive(true)
		await tap([.a, .b]); await tap([.x])
		XCTAssertEqual(actionCount(99), 0)
		relay.setRemoteSessionActive(false)
		await tap([.a, .b]); await tap([.x])
		XCTAssertEqual(actionCount(99), 1)
	}

	func testInputTimelinePreservesChordBoundaries() async {
		let log = InputLogService()
		log.log(buttons: sequence.steps, type: .sequence, action: "(unmapped)", sequenceSteps: sequence.inputSteps)
		await waitForTasks(0.08)
		XCTAssertEqual(log.entries.first?.sequenceSteps, sequence.inputSteps)
	}

}
