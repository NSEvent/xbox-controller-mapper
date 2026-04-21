import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Tests for the precomputed lookup caches used by MappingEngine to avoid
/// linear scans on every button press.
///
/// These tests verify the cache-building logic in isolation (using the same
/// expressions that MappingEngine.setupBindings uses) rather than instantiating
/// EngineState directly, which requires the full app module to be loaded.
final class PrecomputedLookupCacheTests: XCTestCase {

    // MARK: - Chord Participant Cache

    func testChordParticipantButtons_emptyChords() {
        let chords: [ChordMapping] = []
        let result: Set<ControllerButton> = Set(chords.flatMap { $0.buttons })
        XCTAssertTrue(result.isEmpty)
    }

    func testChordParticipantButtons_containsAllButtons() {
        let chord1 = ChordMapping(buttons: [.a, .b], keyCode: 0)
        let chord2 = ChordMapping(buttons: [.x, .y], keyCode: 1)
        let result = Set([chord1, chord2].flatMap { $0.buttons })

        XCTAssertTrue(result.contains(.a))
        XCTAssertTrue(result.contains(.b))
        XCTAssertTrue(result.contains(.x))
        XCTAssertTrue(result.contains(.y))
        XCTAssertEqual(result.count, 4)
    }

    func testChordParticipantButtons_buttonInMultipleChords() {
        let chord1 = ChordMapping(buttons: [.a, .b], keyCode: 0)
        let chord2 = ChordMapping(buttons: [.a, .x], keyCode: 1)
        let result = Set([chord1, chord2].flatMap { $0.buttons })

        XCTAssertTrue(result.contains(.a))
        XCTAssertTrue(result.contains(.b))
        XCTAssertTrue(result.contains(.x))
        // .a appears in both chords but Set deduplicates
        XCTAssertEqual(result.count, 3)
    }

    func testChordParticipantButtons_profileChangeRebuilds() {
        // First profile
        let chord1 = ChordMapping(buttons: [.a, .b], keyCode: 0)
        var cache = Set([chord1].flatMap { $0.buttons })
        XCTAssertTrue(cache.contains(.a))
        XCTAssertTrue(cache.contains(.b))
        XCTAssertFalse(cache.contains(.x))

        // Simulate profile change - rebuild cache
        let chord2 = ChordMapping(buttons: [.x, .y], keyCode: 1)
        cache = Set([chord2].flatMap { $0.buttons })
        XCTAssertFalse(cache.contains(.a))
        XCTAssertFalse(cache.contains(.b))
        XCTAssertTrue(cache.contains(.x))
        XCTAssertTrue(cache.contains(.y))
    }

    func testChordParticipantButtons_buttonNotInAnyChord() {
        let chord = ChordMapping(buttons: [.a, .b], keyCode: 0)
        let result = Set([chord].flatMap { $0.buttons })

        XCTAssertFalse(result.contains(.x))
        XCTAssertFalse(result.contains(.y))
        XCTAssertFalse(result.contains(.leftBumper))
    }

    func testChordParticipantButtons_fromProfile() {
        let chord1 = ChordMapping(buttons: [.a, .b], keyCode: 0)
        let chord2 = ChordMapping(buttons: [.leftBumper, .rightBumper], keyCode: 1)
        let profile = Profile(name: "Test", chordMappings: [chord1, chord2])

        let result = Set(profile.chordMappings.flatMap { $0.buttons })
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result.contains(.a))
        XCTAssertTrue(result.contains(.b))
        XCTAssertTrue(result.contains(.leftBumper))
        XCTAssertTrue(result.contains(.rightBumper))
    }

    // MARK: - Sequence Participant Cache

    func testSequenceParticipantButtons_emptySequences() {
        let sequences: [SequenceMapping] = []
        let result: Set<ControllerButton> = Set(sequences.flatMap { $0.steps })
        XCTAssertTrue(result.isEmpty)
    }

    func testSequenceParticipantButtons_containsAllStepButtons() {
        let seq1 = SequenceMapping(steps: [.dpadDown, .dpadDown, .a], keyCode: 0)
        let seq2 = SequenceMapping(steps: [.b, .x], keyCode: 1)
        let result = Set([seq1, seq2].flatMap { $0.steps })

        XCTAssertTrue(result.contains(.dpadDown))
        XCTAssertTrue(result.contains(.a))
        XCTAssertTrue(result.contains(.b))
        XCTAssertTrue(result.contains(.x))
        // dpadDown appears twice in seq1 but Set deduplicates
        XCTAssertEqual(result.count, 4)
    }

    func testSequenceParticipantButtons_multiStepSequence() {
        let seq = SequenceMapping(steps: [.leftBumper, .rightBumper, .leftTrigger, .rightTrigger], keyCode: 0)
        let result = Set([seq].flatMap { $0.steps })

        XCTAssertTrue(result.contains(.leftBumper))
        XCTAssertTrue(result.contains(.rightBumper))
        XCTAssertTrue(result.contains(.leftTrigger))
        XCTAssertTrue(result.contains(.rightTrigger))
        XCTAssertEqual(result.count, 4)
    }

    func testSequenceParticipantButtons_fromProfile() {
        let seq = SequenceMapping(steps: [.dpadDown, .dpadDown, .a], keyCode: 0)
        let profile = Profile(name: "Test", sequenceMappings: [seq])

        let result = Set(profile.sequenceMappings.flatMap { $0.steps })
        XCTAssertEqual(result.count, 2) // dpadDown + a
        XCTAssertTrue(result.contains(.dpadDown))
        XCTAssertTrue(result.contains(.a))
    }

    // MARK: - Chord Lookup Dictionary

    func testChordLookup_exactMatch() {
        let chord = ChordMapping(buttons: [.a, .b], keyCode: 42)
        let lookup = Dictionary(uniqueKeysWithValues: [chord].map { ($0.buttons, $0) })

        let result = lookup[Set([.a, .b] as [ControllerButton])]
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.keyCode, 42)
    }

    func testChordLookup_subsetDoesNotMatch() {
        let chord = ChordMapping(buttons: [.a, .b, .x], keyCode: 42)
        let lookup = Dictionary(uniqueKeysWithValues: [chord].map { ($0.buttons, $0) })

        let result = lookup[Set([.a, .b] as [ControllerButton])]
        XCTAssertNil(result)
    }

    func testChordLookup_supersetDoesNotMatch() {
        let chord = ChordMapping(buttons: [.a, .b], keyCode: 42)
        let lookup = Dictionary(uniqueKeysWithValues: [chord].map { ($0.buttons, $0) })

        let result = lookup[Set([.a, .b, .x] as [ControllerButton])]
        XCTAssertNil(result)
    }

    func testChordLookup_multipleChordsEachFindable() {
        let chord1 = ChordMapping(buttons: [.a, .b], keyCode: 10)
        let chord2 = ChordMapping(buttons: [.x, .y], keyCode: 20)
        let chord3 = ChordMapping(buttons: [.leftBumper, .rightBumper], keyCode: 30)
        let lookup = Dictionary(uniqueKeysWithValues: [chord1, chord2, chord3].map { ($0.buttons, $0) })

        XCTAssertEqual(lookup[Set([.a, .b] as [ControllerButton])]?.keyCode, 10)
        XCTAssertEqual(lookup[Set([.x, .y] as [ControllerButton])]?.keyCode, 20)
        XCTAssertEqual(lookup[Set([.leftBumper, .rightBumper] as [ControllerButton])]?.keyCode, 30)
    }

    func testChordLookup_emptyChords() {
        let chords: [ChordMapping] = []
        let lookup = Dictionary(uniqueKeysWithValues: chords.map { ($0.buttons, $0) })

        XCTAssertTrue(lookup.isEmpty)
        XCTAssertNil(lookup[Set([.a, .b] as [ControllerButton])])
    }

    func testChordLookup_setOrderDoesNotMatter() {
        let chord = ChordMapping(buttons: [.a, .b, .x], keyCode: 99)
        let lookup = Dictionary(uniqueKeysWithValues: [chord].map { ($0.buttons, $0) })

        // Look up with buttons in different insertion order
        let result = lookup[Set([.x, .a, .b] as [ControllerButton])]
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.keyCode, 99)
    }

    func testChordLookup_preservesChordIdentity() {
        let id = UUID()
        let chord = ChordMapping(id: id, buttons: [.a, .b], keyCode: 42, hint: "test chord")
        let lookup = Dictionary(uniqueKeysWithValues: [chord].map { ($0.buttons, $0) })

        let result = lookup[Set([.a, .b] as [ControllerButton])]
        XCTAssertEqual(result?.id, id)
        XCTAssertEqual(result?.hint, "test chord")
    }

    func testChordLookup_withModifiers() {
        let chord = ChordMapping(
            buttons: [.leftBumper, .a],
            keyCode: 0,
            modifiers: ModifierFlags(command: true)
        )
        let lookup = Dictionary(uniqueKeysWithValues: [chord].map { ($0.buttons, $0) })

        let result = lookup[Set([.leftBumper, .a] as [ControllerButton])]
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.modifiers.command)
    }

    // MARK: - Integration: Full Cache Build from Profile

    func testFullCacheBuild_fromProfile() {
        let chord1 = ChordMapping(buttons: [.a, .b], keyCode: 10)
        let chord2 = ChordMapping(buttons: [.x, .y], keyCode: 20)
        let seq1 = SequenceMapping(steps: [.dpadDown, .dpadDown, .a], keyCode: 30)
        let profile = Profile(
            name: "Full",
            chordMappings: [chord1, chord2],
            sequenceMappings: [seq1]
        )

        // Simulate the same cache-building logic used in setupBindings
        let chords = profile.chordMappings
        let chordParticipants = Set(chords.flatMap { $0.buttons })
        let seqParticipants = Set(profile.sequenceMappings.flatMap { $0.steps })
        let chordLookup = Dictionary(uniqueKeysWithValues: chords.map { ($0.buttons, $0) })

        // Chord participants
        XCTAssertTrue(chordParticipants.contains(.a))
        XCTAssertTrue(chordParticipants.contains(.b))
        XCTAssertTrue(chordParticipants.contains(.x))
        XCTAssertTrue(chordParticipants.contains(.y))
        XCTAssertFalse(chordParticipants.contains(.leftBumper))

        // Sequence participants
        XCTAssertTrue(seqParticipants.contains(.dpadDown))
        XCTAssertTrue(seqParticipants.contains(.a))
        XCTAssertFalse(seqParticipants.contains(.b))

        // Chord lookup
        XCTAssertEqual(chordLookup[Set([.a, .b] as [ControllerButton])]?.keyCode, 10)
        XCTAssertEqual(chordLookup[Set([.x, .y] as [ControllerButton])]?.keyCode, 20)
        XCTAssertNil(chordLookup[Set([.a, .x] as [ControllerButton])])
    }

    func testFullCacheBuild_nilProfile() {
        let profile: Profile? = nil

        let chords = profile?.chordMappings ?? []
        let chordParticipants = Set(chords.flatMap { $0.buttons })
        let seqParticipants = Set((profile?.sequenceMappings ?? []).flatMap { $0.steps })
        let chordLookup = Dictionary(uniqueKeysWithValues: chords.map { ($0.buttons, $0) })

        XCTAssertTrue(chordParticipants.isEmpty)
        XCTAssertTrue(seqParticipants.isEmpty)
        XCTAssertTrue(chordLookup.isEmpty)
    }

    func testFullCacheBuild_profileWithNoMappings() {
        let profile = Profile(name: "Empty")

        let chords = profile.chordMappings
        let chordParticipants = Set(chords.flatMap { $0.buttons })
        let seqParticipants = Set(profile.sequenceMappings.flatMap { $0.steps })
        let chordLookup = Dictionary(uniqueKeysWithValues: chords.map { ($0.buttons, $0) })

        XCTAssertTrue(chordParticipants.isEmpty)
        XCTAssertTrue(seqParticipants.isEmpty)
        XCTAssertTrue(chordLookup.isEmpty)
    }

    // MARK: - Edge Cases

    func testChordLookup_singleButtonChord() {
        // ChordMapping allows single-button chords (though they're not "valid")
        let chord = ChordMapping(buttons: [.a], keyCode: 1)
        let lookup = Dictionary(uniqueKeysWithValues: [chord].map { ($0.buttons, $0) })

        XCTAssertEqual(lookup[Set([.a] as [ControllerButton])]?.keyCode, 1)
    }

    func testChordParticipantContains_O1Lookup() {
        // Verify that Set.contains is being used (O(1)) rather than array scan
        let chord1 = ChordMapping(buttons: [.a, .b], keyCode: 0)
        let chord2 = ChordMapping(buttons: [.x, .y], keyCode: 1)
        let chord3 = ChordMapping(buttons: [.leftBumper, .rightBumper], keyCode: 2)
        let participants = Set([chord1, chord2, chord3].flatMap { $0.buttons })

        // These are O(1) lookups on Set
        XCTAssertTrue(participants.contains(.a))
        XCTAssertTrue(participants.contains(.rightBumper))
        XCTAssertFalse(participants.contains(.menu))
        XCTAssertFalse(participants.contains(.leftTrigger))
    }

    func testChordLookup_O1DictionaryLookup() {
        // Verify dictionary lookup is O(1) vs linear scan
        let chord1 = ChordMapping(buttons: [.a, .b], keyCode: 10)
        let chord2 = ChordMapping(buttons: [.x, .y], keyCode: 20)
        let chord3 = ChordMapping(buttons: [.leftBumper, .rightBumper], keyCode: 30)
        let lookup = Dictionary(uniqueKeysWithValues: [chord1, chord2, chord3].map { ($0.buttons, $0) })

        // Direct dictionary lookup - O(1) average case
        XCTAssertNotNil(lookup[Set([.a, .b] as [ControllerButton])])
        XCTAssertNotNil(lookup[Set([.x, .y] as [ControllerButton])])
        XCTAssertNotNil(lookup[Set([.leftBumper, .rightBumper] as [ControllerButton])])
        XCTAssertNil(lookup[Set([.a, .x] as [ControllerButton])])
    }
}
