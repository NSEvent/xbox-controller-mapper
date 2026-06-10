import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

// MARK: - Chord Conflict Detection Tests

final class ChordConflictTests: XCTestCase {

    // MARK: - Basic Conflict Detection

    func testNoConflictWhenNoExistingChords() {
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing: [ChordMapping] = []

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testNoConflictWhenNoButtonsSelected() {
        let selected: Set<ControllerButton> = []
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty, "Should not conflict when no buttons are selected")
    }

    func testSingleButtonSelectedConflictsWithTwoButtonChord() {
        // Existing chord: Left + Down
        // User selects: Left
        // Expected conflict: Down (because Left + Down already exists)
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.dpadDown])
    }

    func testSingleButtonSelectedNoConflictWithUnrelatedChord() {
        // Existing chord: A + B
        // User selects: Left
        // Expected: No conflict (Left is not part of the A+B chord)
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(buttons: [.a, .b], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty)
    }

    // MARK: - Multi-Button Selection

    func testTwoButtonsSelectedConflictsWithThreeButtonChord() {
        // Existing chord: Left + Down + Right
        // User selects: Left + Down
        // Expected conflict: Right (would complete the 3-button chord)
        let selected: Set<ControllerButton> = [.dpadLeft, .dpadDown]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown, .dpadRight], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.dpadRight])
    }

    func testNoConflictWhenMoreThanOneButtonRemains() {
        // Existing chord: Left + Down + Right
        // User selects: Left
        // Expected: No conflict (adding Down or Right alone won't complete the chord)
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown, .dpadRight], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty, "Should not conflict when more than one button is needed to complete chord")
    }

    // MARK: - Multiple Existing Chords

    func testMultipleConflictsFromDifferentChords() {
        // Existing chords: Left + Down, Left + Up
        // User selects: Left
        // Expected conflicts: Down, Up (both would create duplicates)
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0),
            ChordMapping(buttons: [.dpadLeft, .dpadUp], keyCode: 1)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.dpadDown, .dpadUp])
    }

    func testPartialOverlapWithMultipleChords() {
        // Existing chords: A + B, A + B + X
        // User selects: A + B
        // Expected: X is conflicted (completes A+B+X), but A+B itself is already a chord (handled by chordAlreadyExists)
        let selected: Set<ControllerButton> = [.a, .b]
        let existing = [
            ChordMapping(buttons: [.a, .b], keyCode: 0),
            ChordMapping(buttons: [.a, .b, .x], keyCode: 1)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.x])
    }

    // MARK: - Edit Mode (Exclude Current Chord)

    func testEditModeExcludesCurrentChord() {
        // Existing chord: Left + Down (ID: xxx)
        // User is editing chord xxx and has Left + Down selected
        // Selects just Left
        // Expected: No conflict for Down (we're editing the very chord that has Left + Down)
        let chordId = UUID()
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(id: chordId, buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing,
            editingChordId: chordId
        )

        XCTAssertTrue(conflicts.isEmpty, "Should not conflict with the chord being edited")
    }

    func testEditModeStillConflictsWithOtherChords() {
        // Existing chords: Left + Down (ID: xxx), Left + Up (ID: yyy)
        // User is editing chord xxx and selects Left
        // Expected: Up is conflicted (from chord yyy), Down is NOT (from chord xxx being edited)
        let chordIdX = UUID()
        let chordIdY = UUID()
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(id: chordIdX, buttons: [.dpadLeft, .dpadDown], keyCode: 0),
            ChordMapping(id: chordIdY, buttons: [.dpadLeft, .dpadUp], keyCode: 1)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing,
            editingChordId: chordIdX
        )

        XCTAssertEqual(conflicts, [.dpadUp])
    }

    // MARK: - Edge Cases

    func testSelectedButtonsMatchExistingChordExactly() {
        // Existing chord: Left + Down
        // User selects: Left + Down (exact match)
        // Expected: No additional conflicts (the duplicate is handled by chordAlreadyExists, not conflictedButtons)
        let selected: Set<ControllerButton> = [.dpadLeft, .dpadDown]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty, "Exact match handled by chordAlreadyExists, not conflictedButtons")
    }

    func testSelectedButtonsSupersetOfExistingChord() {
        // Existing chord: Left + Down
        // User selects: Left + Down + Right (superset)
        // Expected: No conflict (selected is already larger than existing chord)
        let selected: Set<ControllerButton> = [.dpadLeft, .dpadDown, .dpadRight]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testNoConflictWithDisjointSets() {
        // Existing chord: A + B
        // User selects: X + Y
        // Expected: No conflict (completely disjoint)
        let selected: Set<ControllerButton> = [.x, .y]
        let existing = [
            ChordMapping(buttons: [.a, .b], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testComplexScenarioMultipleChordsMultipleConflicts() {
        // Existing chords:
        //   - LB + RB
        //   - LB + A
        //   - LB + A + B (3-button)
        //   - X + Y
        // User selects: LB
        // Expected conflicts: RB (from LB+RB), A (from LB+A)
        // Note: LB+A+B requires 2 more buttons, so no conflict from that
        let selected: Set<ControllerButton> = [.leftBumper]
        let existing = [
            ChordMapping(buttons: [.leftBumper, .rightBumper], keyCode: 0),
            ChordMapping(buttons: [.leftBumper, .a], keyCode: 1),
            ChordMapping(buttons: [.leftBumper, .a, .b], keyCode: 2),
            ChordMapping(buttons: [.x, .y], keyCode: 3)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.rightBumper, .a])
    }

    // MARK: - Conflict With Chord Info Tests

    func testConflictedButtonsWithChordsReturnsCorrectChord() {
        // Existing chord: Left + Down
        // User selects: Left
        // Expected: Down maps to the Left + Down chord
        let selected: Set<ControllerButton> = [.dpadLeft]
        let chord = ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        let existing = [chord]

        let conflicts = ChordMapping.conflictedButtonsWithChords(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[.dpadDown]?.buttons, chord.buttons)
    }

    func testConflictedButtonsWithChordsMultipleConflicts() {
        // Existing chords: LB + RB, LB + A
        // User selects: LB
        // Expected: RB maps to LB+RB chord, A maps to LB+A chord
        let selected: Set<ControllerButton> = [.leftBumper]
        let chord1 = ChordMapping(buttons: [.leftBumper, .rightBumper], keyCode: 0)
        let chord2 = ChordMapping(buttons: [.leftBumper, .a], keyCode: 1)
        let existing = [chord1, chord2]

        let conflicts = ChordMapping.conflictedButtonsWithChords(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts.count, 2)
        XCTAssertEqual(conflicts[.rightBumper]?.buttons, chord1.buttons)
        XCTAssertEqual(conflicts[.a]?.buttons, chord2.buttons)
    }
}
