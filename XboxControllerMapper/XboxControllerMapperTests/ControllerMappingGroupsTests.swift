import XCTest
@testable import ControllerKeys

@MainActor
final class ControllerMappingGroupsTests: MappingEngineTestCase {
	private let pedal = ControllerVisualDescriptor(family: .footPedal)
	private func chord(_ buttons: Set<ControllerButton>, _ hint: String) -> ChordMapping { ChordMapping(buttons: buttons, keyCode: 12, hint: hint) }

	func testStableGroupingRequiresEveryButtonAndDoesNotChangeStoredOrder() {
		let gamepad = chord([.a, .b], "Gamepad")
		let first = chord([.footPedalLeft, .footPedalMiddle], "First pedal")
		let mixed = chord([.footPedalRight, .a], "Mixed")
		let second = chord([.footPedalLeft, .footPedalRight], "Second pedal")
		let mappings = [gamepad, first, mixed, second]
		let groups = ControllerMappingGroups.sections(of: mappings, descriptor: pedal, buttons: { $0.buttons })
		XCTAssertEqual(groups.map(\.title), ["For VEC Infinity Pedal", "Other mappings"])
		XCTAssertEqual(groups[0].items.map(\.id), [first.id, second.id])
		XCTAssertEqual(groups[1].items.map(\.id), [gamepad.id, mixed.id])
		XCTAssertEqual(mappings.map(\.id), [gamepad.id, first.id, mixed.id, second.id])
	}

	func testSequenceCompatibilityIncludesEveryStepAndRepeatedButtons() {
		let mixed = SequenceMapping(steps: [.footPedalLeft, .a], keyCode: 12)
		let repeated = SequenceMapping(steps: [.footPedalLeft, .footPedalLeft], keyCode: 13)
		let groups = ControllerMappingGroups.sections(of: [mixed, repeated], descriptor: pedal, buttons: { Set($0.steps) })
		XCTAssertEqual(groups[0].items, [repeated])
		XCTAssertEqual(groups[1].items, [mixed])
	}

	func testNoSelectedControllerKeepsOneListAndEmptyCompatibleSectionIsExplained() {
		let mappings = [chord([.a, .b], "Gamepad")]
		XCTAssertEqual(ControllerMappingGroups.sections(of: mappings, descriptor: nil, buttons: { $0.buttons }).map(\.title), ["All mappings"])
		let groups = ControllerMappingGroups.sections(of: mappings, descriptor: pedal, buttons: { $0.buttons })
		XCTAssertTrue(groups[0].items.isEmpty)
		XCTAssertEqual(groups[1].items, mappings)
	}

	func testSharedDpadIsCompatibleWithRemoteAndGamepadButNotPedal() {
		let mapping = chord([.dpadUp, .dpadRight], "Shared")
		for family: ControllerVisualFamily in [.xiaomiRemote, .xbox, .footPedal] {
			let groups = ControllerMappingGroups.sections(of: [mapping], descriptor: .init(family: family), buttons: { $0.buttons })
			XCTAssertEqual(groups[0].items.isEmpty, family == .footPedal)
		}
	}

	func testReorderingPedalsPreservesOtherDevicesSlotsAndPersists() throws {
		let gamepad = chord([.a, .b], "Gamepad")
		let first = chord([.footPedalLeft, .footPedalMiddle], "First pedal")
		let remote = chord([.xiaomiOK, .xiaomiHome], "Remote")
		let second = chord([.footPedalLeft, .footPedalRight], "Second pedal")
		var profile = Profile(name: "Grouped")
		profile.chordMappings = [gamepad, first, remote, second]
		profileManager.setActiveProfile(profile)
		profileManager.moveChordSection(ids: [first.id, second.id], from: [0], to: 2, profileId: profile.id)
		let expected = [gamepad, second, remote, first]
		XCTAssertEqual(profileManager.activeProfile?.chordMappings, expected)
		profileManager.flushPendingSaves()
		let restored = ProfileManager(configDirectoryOverride: testConfigDirectory)
		XCTAssertEqual(restored.activeProfile?.chordMappings, expected)
	}

	func testSequenceReorderThenDeleteTargetsTheVisibleMappingByID() {
		let gamepad = SequenceMapping(steps: [.a, .b], keyCode: 12)
		let first = SequenceMapping(steps: [.footPedalLeft, .footPedalMiddle], keyCode: 13)
		let second = SequenceMapping(steps: [.footPedalRight, .footPedalLeft], keyCode: 14)
		var profile = Profile(name: "Grouped")
		profile.sequenceMappings = [first, gamepad, second]
		profileManager.setActiveProfile(profile)
		profileManager.moveSequenceSection(ids: [first.id, second.id], from: [1], to: 0, profileId: profile.id)
		profileManager.removeSequence(first)
		XCTAssertEqual(profileManager.activeProfile?.sequenceMappings, [second, gamepad])
	}

	func testStaleDragCannotWriteIntoAnotherProfileOrUseChangedOffsets() {
		let a = chord([.footPedalLeft, .footPedalMiddle], "A")
		let b = chord([.footPedalLeft, .footPedalRight], "B")
		var first = Profile(name: "First"); first.chordMappings = [a, b]
		var second = Profile(name: "Copy"); second.chordMappings = [a, b]
		profileManager.setActiveProfile(first)
		profileManager.setActiveProfile(second)
		profileManager.moveChordSection(ids: [a.id, b.id], from: [0], to: 2, profileId: first.id)
		XCTAssertEqual(profileManager.activeProfile?.chordMappings, [a, b])
		XCTAssertNil(ControllerMappingGroups.moving([b, a], visibleIDs: [a.id, b.id], from: [0], to: 2))
		XCTAssertNil(ControllerMappingGroups.moving([a], visibleIDs: [a.id, b.id], from: [0], to: 2))
		XCTAssertNil(ControllerMappingGroups.moving([a, b], visibleIDs: [a.id, b.id], from: [2], to: 0))
	}
}
