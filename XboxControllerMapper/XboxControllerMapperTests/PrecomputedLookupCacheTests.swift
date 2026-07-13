import XCTest
@testable import ControllerKeys

/// Tests for the profile-derived lookup tables used by MappingEngine to avoid
/// linear scans on every button press.
final class PrecomputedLookupCacheTests: XCTestCase {
    func testMappingProfileIndexBuildsLookupTablesFromProfile() {
		let chord1 = ChordMapping(buttons: [.a, .b], keyCode: 10, hint: "first")
		let chord2 = ChordMapping(
			buttons: [.leftBumper, .rightBumper],
			keyCode: 20,
			modifiers: ModifierFlags(command: true),
			hint: "second"
		)
		let sequence = SequenceMapping(steps: [.dpadDown, .dpadDown, .a], keyCode: 30)
		let layerID = UUID()
		let layer = Layer(
			id: layerID,
			name: "Navigation",
			activatorButton: .leftThumbstick,
			buttonMappings: [.a: KeyMapping(keyCode: 8)]
		)
		let profile = Profile(
			name: "Indexed",
			chordMappings: [chord1, chord2],
			sequenceMappings: [sequence],
			layers: [layer]
		)

		let index = MappingProfileIndex(profile: profile)

		XCTAssertEqual(index.chordParticipantButtons, Set([.a, .b, .leftBumper, .rightBumper] as [ControllerButton]))
		XCTAssertEqual(index.sequenceParticipantButtons, Set([.dpadDown, .a] as [ControllerButton]))

		let firstLookup = index.chordLookup[Set([.b, .a] as [ControllerButton])]
		XCTAssertEqual(firstLookup?.keyCode, 10)
		XCTAssertEqual(firstLookup?.hint, "first")

		let secondLookup = index.chordLookup[Set([.leftBumper, .rightBumper] as [ControllerButton])]
		XCTAssertEqual(secondLookup?.keyCode, 20)
		XCTAssertTrue(secondLookup?.modifiers.command == true)

		XCTAssertNil(index.chordLookup[Set([.a] as [ControllerButton])], "Subsets should not match")
		XCTAssertNil(index.chordLookup[Set([.a, .b, .x] as [ControllerButton])], "Supersets should not match")
		XCTAssertEqual(index.layersById[layerID]?.name, "Navigation")
		XCTAssertEqual(index.layerActivatorMap[.leftThumbstick], layerID)
    }

    func testMappingProfileIndexExpandsPhysicalEquivalentButtons() {
		let chord = ChordMapping(buttons: [.leftPaddle, .rightPaddle], keyCode: 1)
		let sequence = SequenceMapping(steps: [.leftFunction, .rightFunction], keyCode: 2)
		let profile = Profile(
			name: "Physical Equivalents",
			chordMappings: [chord],
			sequenceMappings: [sequence]
		)

		let index = MappingProfileIndex(profile: profile)

		XCTAssertEqual(
			index.chordParticipantButtons,
			Set([.leftPaddle, .rightPaddle, .xboxPaddle1, .xboxPaddle2] as [ControllerButton])
		)
		XCTAssertEqual(
			index.sequenceParticipantButtons,
			Set([.leftFunction, .rightFunction, .xboxPaddle3, .xboxPaddle4] as [ControllerButton])
		)
    }

    func testMappingProfileIndexNilProfileIsEmpty() {
		let index = MappingProfileIndex(profile: nil)

		XCTAssertTrue(index.chordParticipantButtons.isEmpty)
		XCTAssertTrue(index.sequenceParticipantButtons.isEmpty)
		XCTAssertTrue(index.chordLookup.isEmpty)
		XCTAssertTrue(index.layersById.isEmpty)
		XCTAssertTrue(index.layerActivatorMap.isEmpty)
    }

    func testMappingProfileIndexProfileWithNoMappingsIsEmpty() {
		let index = MappingProfileIndex(profile: Profile(name: "Empty"))

		XCTAssertTrue(index.chordParticipantButtons.isEmpty)
		XCTAssertTrue(index.sequenceParticipantButtons.isEmpty)
		XCTAssertTrue(index.chordLookup.isEmpty)
		XCTAssertTrue(index.layersById.isEmpty)
		XCTAssertTrue(index.layerActivatorMap.isEmpty)
    }

    func testMappingProfileIndexSingleButtonChordIsIndexed() {
		let chord = ChordMapping(buttons: [.a], keyCode: 1)
		let profile = Profile(name: "Single Button", chordMappings: [chord])

		let index = MappingProfileIndex(profile: profile)

		XCTAssertEqual(index.chordParticipantButtons, Set([.a] as [ControllerButton]))
		XCTAssertEqual(index.chordLookup[Set([.a] as [ControllerButton])]?.keyCode, 1)
    }

    func testMappingProfileIndexKeepsLastDuplicateChordButtonSet() {
		let first = ChordMapping(buttons: [.a, .b], keyCode: 10, hint: "first")
		let second = ChordMapping(buttons: [.b, .a], keyCode: 20, hint: "second")
		let profile = Profile(name: "Duplicate Chords", chordMappings: [first, second])

		let index = MappingProfileIndex(profile: profile)

		let resolved = index.chordLookup[Set([.a, .b] as [ControllerButton])]
		XCTAssertEqual(resolved?.keyCode, 20)
		XCTAssertEqual(resolved?.hint, "second")
    }

    func testMappingProfileIndexKeepsFirstDuplicateLayerID() {
		let id = UUID()
		let first = Layer(id: id, name: "First", activatorButton: .a)
		let second = Layer(id: id, name: "Second", activatorButton: .b)
		let profile = Profile(name: "Duplicate Layers", layers: [first, second])

		let index = MappingProfileIndex(profile: profile)

		XCTAssertEqual(index.layersById[id]?.name, "First")
		XCTAssertEqual(index.layerActivatorMap[.a], id)
		XCTAssertEqual(index.layerActivatorMap[.b], id)
    }

    func testMappingProfileIndexKeepsLastDuplicateLayerActivator() {
		let first = Layer(id: UUID(), name: "First", activatorButton: .leftBumper)
		let second = Layer(id: UUID(), name: "Second", activatorButton: .leftBumper)
		let profile = Profile(name: "Duplicate Activator", layers: [first, second])

		let index = MappingProfileIndex(profile: profile)

		XCTAssertEqual(index.layerActivatorMap[.leftBumper], second.id)
    }
}
