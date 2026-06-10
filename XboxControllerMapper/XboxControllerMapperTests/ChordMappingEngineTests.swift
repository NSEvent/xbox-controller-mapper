import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Multi-button chord edge cases, chords with modifiers, and chord management on the profile.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class ChordMappingEngineTests: MappingEngineTestCase {

    // MARK: - Multi-Button Chord Edge Cases

    /// Tests chord with 3 buttons
    func testThreeButtonChord() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b, .x], keyCode: 9)
            profileManager.setActiveProfile(Profile(
                name: "Triple",
                buttonMappings: [.a: .key(1), .b: .key(2), .x: .key(3)],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onChordDetected?([.a, .b, .x])
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 9 }
                return false
            }, "Three-button chord should execute")
        }
    }

    /// Tests partial chord match (pressing 2 buttons when 3-button chord exists)
    func testPartialChordNoMatch() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b, .x], keyCode: 9)
            profileManager.setActiveProfile(Profile(
                name: "Triple",
                buttonMappings: [.a: .key(1), .b: .key(2), .x: .key(3)],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Only 2 buttons - should fallback to individual
            controllerService.onChordDetected?([.a, .b])
        }
        await waitForTasks()

        // Release both
        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.05)
            controllerService.onButtonReleased?(.b, 0.05)
        }
        await waitForTasks()

        await MainActor.run {
            // Should NOT execute 3-button chord
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 9 }
                return false
            }, "Three-button chord should not match two-button press")

            // Should execute individual button actions
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Button A should execute on fallback")
        }
    }

    // MARK: - Chord with Modifiers Tests

    /// Tests chord that outputs key + modifiers
    func testChordWithModifiers() async throws {
        await MainActor.run {
            let chord = ChordMapping(
                buttons: [.x, .y],
                keyCode: 50, // some key
                modifiers: ModifierFlags(command: true, shift: true)
            )
            profileManager.setActiveProfile(Profile(
                name: "ChordMod",
                buttonMappings: [:],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onChordDetected?([.x, .y])
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(50, let mods) = event {
                    return mods.contains(.maskCommand) && mods.contains(.maskShift)
                }
                return false
            }, "Chord should output key with modifiers")
        }
    }

    // MARK: - Chord Edge Case Tests

    /// Tests chord where one button has no individual mapping
    func testChordWithUnmappedButton() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b], keyCode: 99)
            profileManager.setActiveProfile(Profile(
                name: "ChordUnmapped",
                buttonMappings: [.a: .key(1)], // Only A mapped, not B
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onChordDetected?([.a, .b])
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(99, _) = event { return true }
                return false
            }, "Chord should work even if one button is unmapped individually")
        }
    }

    /// Tests multiple overlapping chords (2-button vs 3-button)
    func testOverlappingChords() async throws {
        await MainActor.run {
            let twoButtonChord = ChordMapping(buttons: [.a, .b], keyCode: 50)
            let threeButtonChord = ChordMapping(buttons: [.a, .b, .x], keyCode: 51)
            profileManager.setActiveProfile(Profile(
                name: "Overlap",
                buttonMappings: [:],
                chordMappings: [twoButtonChord, threeButtonChord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Trigger 3-button chord
        await MainActor.run {
            controllerService.onChordDetected?([.a, .b, .x])
        }
        await waitForTasks()

        await MainActor.run {
            // Should trigger 3-button chord, not 2-button
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(51, _) = event { return true }
                return false
            }, "3-button chord should be triggered")

            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(50, _) = event { return true }
                return false
            }, "2-button chord should NOT be triggered")
        }
    }

    // MARK: - Chord Management Tests

    /// Tests adding a chord to profile
    func testAddChord() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            let chord = ChordMapping(buttons: [.a, .b], keyCode: 1)
            profileManager.addChord(chord)

            XCTAssertEqual(profileManager.activeProfile?.chordMappings.count, 1)
            XCTAssertEqual(profileManager.activeProfile?.chordMappings.first?.buttons, [.a, .b])
        }
    }

    /// Tests removing a chord from profile
    func testRemoveChord() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b], keyCode: 1)
            let profile = Profile(name: "Test", chordMappings: [chord])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            XCTAssertEqual(profileManager.activeProfile?.chordMappings.count, 1)

            profileManager.removeChord(chord)

            XCTAssertEqual(profileManager.activeProfile?.chordMappings.count, 0)
        }
    }

    /// Tests updating a chord in profile
    func testUpdateChord() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b], keyCode: 1)
            let profile = Profile(name: "Test", chordMappings: [chord])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            var updatedChord = chord
            updatedChord.keyCode = 5

            profileManager.updateChord(updatedChord)

            XCTAssertEqual(profileManager.activeProfile?.chordMappings.first?.keyCode, 5)
        }
    }

}
