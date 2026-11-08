import XCTest
@testable import ControllerKeys

final class MixedSequenceModelTests: XCTestCase {
	func testLegacyRoundTripPreservesActionsAndPressTiming() throws {
		let original = SequenceMapping(steps: [.a, .b], stepTimeout: 0.7, keyCode: 40, hint: "Legacy")
		let data = try JSONEncoder().encode(original)
		let restored = try JSONDecoder().decode(SequenceMapping.self, from: data)
		XCTAssertEqual(restored, original)
		XCTAssertFalse(restored.usesReleaseSteps)
		XCTAssertEqual(restored.inputSteps, [SequenceStep([.a]), SequenceStep([.b])])
		let detector = SequenceDetector()
		detector.configure(sequences: [restored])
		XCTAssertNil(detector.process(.a, at: 0))
		XCTAssertEqual(detector.process(.b, at: 0.1)?.id, original.id, "Legacy still completes on press without any release")
	}

	func testMixedProfileRoundTripKeepsBoundariesOrderIDsAndActions() throws {
		let sequence = SequenceMapping(chordSteps: [SequenceStep([.a, .b]), SequenceStep([.x])],
			stepTimeout: 0.75, keyCode: 12, hint: "Mixed")
		let profile = Profile(name: "Mixed", sequenceMappings: [sequence, SequenceMapping(steps: [.x, .y], keyCode: 14)])
		let restored = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
		XCTAssertEqual(restored.sequenceMappings, profile.sequenceMappings)
		XCTAssertTrue(restored.sequenceMappings[0].usesReleaseSteps)
		XCTAssertEqual(sequence.allButtons, [.a, .b, .x])
		XCTAssertEqual(sequence.clearingAllActions().inputSteps, sequence.inputSteps)
		XCTAssertTrue(sequence.clearingAllActions().usesReleaseSteps)
	}

	func testOlderDecoderRejectsMixedStepsInsteadOfFlattening() throws {
		struct OldSequence: Decodable { let steps: [ControllerButton] }
		let legacy = SequenceMapping(steps: [.a, .b])
		XCTAssertNoThrow(try JSONDecoder().decode(OldSequence.self, from: JSONEncoder().encode(legacy)))
		let mixed = SequenceMapping(chordSteps: [SequenceStep([.a, .b]), SequenceStep([.x])])
		XCTAssertThrowsError(try JSONDecoder().decode(OldSequence.self, from: JSONEncoder().encode(mixed)))
	}

	func testMalformedAndFutureFormatsAreRejected() {
		for json in [
			#"{"stepFormat":2,"steps":[{"buttons":[]},{"buttons":["a"]}]}"#,
			#"{"stepFormat":2,"steps":[]}"#,
			#"{"stepFormat":2,"steps":[{"buttons":["a"]}]}"#,
			#"{"stepFormat":2,"steps":[{"buttons":["unknown"]},{"buttons":["a"]}]}"#,
			#"{"stepFormat":99,"steps":["a","b"]}"#
		] {
			XCTAssertThrowsError(try JSONDecoder().decode(SequenceMapping.self, from: Data(json.utf8)), json)
		}
	}

	func testStepCanonicalizationAndDirectionalAliases() throws {
		let json = Data(#"{"buttons":["b","a","b"]}"#.utf8)
		XCTAssertEqual(try JSONDecoder().decode(SequenceStep.self, from: json), SequenceStep([.a, .b]))
		XCTAssertTrue(SequenceStep([.touchpadButton, .a]).matches(SequenceStep([.touchpadRegionTopLeftClick, .a])))
		XCTAssertFalse(SequenceStep([.touchpadRegionTopLeftClick]).matches(SequenceStep([.touchpadButton])))
		XCTAssertFalse(SequenceStep([.touchpadButton]).matches(SequenceStep([.touchpadRegionTopLeftClick, .touchpadRegionTopRightClick])))
	}

	func testManualSelectionNeedsExplicitCommitAndCanBeCancelled() {
		var draft = SequenceEditorDraft()
		draft.toggle(.a); draft.toggle(.b)
		XCTAssertTrue(draft.steps.isEmpty)
		XCTAssertFalse(draft.canSave)
		draft.commitStep()
		XCTAssertEqual(draft.steps, [SequenceStep([.a, .b])])
		draft.edit(); draft.toggle(.x); draft.commitStep()
		XCTAssertTrue(draft.canSave)
		draft.edit(0); draft.toggle(.y); draft.cancelStep()
		XCTAssertEqual(draft.steps[0], SequenceStep([.a, .b]))
	}

	func testEditingReorderingDuplicatingAndDeletingKeepWholeChords() {
		var draft = SequenceEditorDraft()
		draft.useRecording([SequenceStep([.a, .b]), SequenceStep([.x])])
		draft.duplicate(0); draft.move(2, by: -1); draft.remove(0)
		XCTAssertEqual(draft.steps, [SequenceStep([.x]), SequenceStep([.a, .b])])
		draft.edit(1); draft.toggle(.b); draft.toggle(.y); draft.commitStep()
		XCTAssertEqual(draft.steps[1], SequenceStep([.a, .y]))
	}

	func testLegacyDraftConvertsOnlyWhenChordOrRecordingIsAccepted() {
		var draft = SequenceEditorDraft()
		draft.load(SequenceMapping(steps: [.a, .b]))
		draft.edit(0); draft.toggle(.x); draft.cancelStep()
		XCTAssertFalse(draft.usesReleaseSteps)
		draft.edit(0); draft.toggle(.x); draft.commitStep()
		XCTAssertTrue(draft.usesReleaseSteps)
	}

	func testInvalidManualStepAndStepLimitAreEnforced() {
		// Axis movement mappings can hold adjacent cardinal directions together.
		XCTAssertNil(SequenceStep([.leftStickUp, .leftStickRight]).validationMessage)
		XCTAssertNotNil(SequenceStep([.leftStickUp, .leftStickDown]).validationMessage)
		var draft = SequenceEditorDraft()
		draft.toggle(.dpadUp); draft.toggle(.dpadDown)
		XCTAssertNotNil(draft.selectionError)
		draft.commitStep(); XCTAssertTrue(draft.steps.isEmpty)
		draft.useRecording(Array(repeating: SequenceStep([.a]), count: Config.maxSequenceSteps))
		draft.duplicate(0); XCTAssertEqual(draft.steps.count, Config.maxSequenceSteps)
		draft.edit(); draft.toggle(.b); draft.commitStep()
		XCTAssertEqual(draft.steps.count, Config.maxSequenceSteps)
	}

	func testCompatibilityRequiresEveryMemberOfEveryStep() {
		let pedal = SequenceMapping(chordSteps: [SequenceStep([.footPedalLeft, .footPedalRight]), SequenceStep([.footPedalMiddle])])
		let crossDevice = SequenceMapping(chordSteps: [SequenceStep([.footPedalLeft, .a]), SequenceStep([.footPedalMiddle])])
		let groups = ControllerMappingGroups.sections(of: [crossDevice, pedal], descriptor: ControllerVisualDescriptor(family: .footPedal), buttons: { $0.allButtons })
		XCTAssertEqual(groups[0].items.map(\.id), [pedal.id])
		XCTAssertEqual(groups[1].items.map(\.id), [crossDevice.id])
		XCTAssertTrue(pedal.stepsDisplayString.contains(" + "))
		XCTAssertTrue(pedal.stepsDisplayString.contains(" → "))
	}
	func testInvalidInMemoryMixedMappingsCannotExportAsDifferentTriggers() throws {
		var sequence = SequenceMapping(chordSteps: [SequenceStep([.a, .b]), SequenceStep([.x])])
		sequence.usesReleaseSteps = false
		XCTAssertFalse(sequence.isValid)
		XCTAssertThrowsError(try JSONEncoder().encode(sequence))
		sequence.usesReleaseSteps = true
		sequence.inputSteps = [SequenceStep([]), SequenceStep([.x])]
		XCTAssertThrowsError(try JSONEncoder().encode(sequence))
		sequence.inputSteps = Array(repeating: SequenceStep([.a]), count: Config.maxSequenceSteps + 1)
		XCTAssertFalse(sequence.isValid)
		XCTAssertThrowsError(try JSONEncoder().encode(sequence))
	}

}
