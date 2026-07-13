import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Modifier tap/hold behavior, key + modifier combos, function keys, and modifier overlap across buttons.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class ModifierAndComboTests: MappingEngineTestCase {

    // MARK: - Modifier Tap (Non-Hold) Edge Cases

    /// Tests modifier-only mapping (tap, not hold) releases after delay
    func testModifierTapReleasesAfterDelay() async throws {
        await MainActor.run {
            // Non-hold modifier (tap)
            let mapping = KeyMapping(modifiers: ModifierFlags(command: true), isHoldModifier: false)
            profileManager.setActiveProfile(Profile(name: "ModTap", buttonMappings: [.a: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.emitInputEvent(.buttonPressed(.a))
            controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.05))
        }
        await waitForTasks()

        await MainActor.run {
            // Should have both hold and release modifier events
            let holdCount = mockInputSimulator.events.filter { event in
                if case .holdModifier = event { return true }
                return false
            }.count
            let releaseCount = mockInputSimulator.events.filter { event in
                if case .releaseModifier = event { return true }
                return false
            }.count

            XCTAssertGreaterThan(holdCount, 0, "Modifier tap should hold modifier")
            XCTAssertGreaterThan(releaseCount, 0, "Modifier tap should release modifier after delay")
        }
    }

    // MARK: - Multiple Modifier Hold Tests

    /// Tests holding multiple different modifiers on different buttons
    func testMultipleModifiersOnDifferentButtons() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "MultiMod", buttonMappings: [
                .leftBumper: .holdModifier(.command),
                .rightBumper: .holdModifier(.option),
                .leftTrigger: .holdModifier(.shift)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press all three
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
            controllerService.buttonPressed(.rightBumper)
            controllerService.buttonPressed(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held")
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskAlternate), "Option should be held")
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift), "Shift should be held")
        }

        // Release in different order
        await MainActor.run {
            controllerService.buttonReleased(.rightBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should still be held")
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskAlternate), "Option should be released")
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift), "Shift should still be held")
        }

        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
            controllerService.buttonReleased(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.isEmpty, "All modifiers should be released")
        }
    }

    // MARK: - Key + Modifier Combo Tests

    /// Tests complex key + modifier combination
    func testComplexKeyCombination() async throws {
        await MainActor.run {
            // Cmd + Opt + Shift + K
            let mapping = KeyMapping(
                keyCode: 40, // 'k'
                modifiers: ModifierFlags(command: true, option: true, shift: true)
            )
            profileManager.setActiveProfile(Profile(name: "Complex", buttonMappings: [.y: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.y)
            controllerService.buttonReleased(.y)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(40, let mods) = event {
                    return mods.contains(.maskCommand) &&
                           mods.contains(.maskAlternate) &&
                           mods.contains(.maskShift)
                }
                return false
            }, "Should press key with all three modifiers")
        }
    }

    // MARK: - Function Key Tests

    /// Tests function key mappings
    func testFunctionKeyMappings() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "FnKeys", buttonMappings: [
                .a: .key(KeyCodeMapping.f1),
                .b: .key(KeyCodeMapping.f12)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.f1 }
                return false
            }, "Should press F1")
        }

        await MainActor.run {
            controllerService.buttonPressed(.b)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.f12 }
                return false
            }, "Should press F12")
        }
    }

    // MARK: - Modifier Key Overlap Tests

    /// Tests the same modifier on multiple buttons
    func testSameModifierOnMultipleButtons() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "DualCmd", buttonMappings: [
                .leftBumper: .holdModifier(.command),
                .rightBumper: .holdModifier(.command) // Same modifier!
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press both
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held")
        }

        // Release one - should still be held
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should STILL be held (RB holds it)")
        }

        // Release the other - now should be released
        await MainActor.run {
            controllerService.buttonReleased(.rightBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should now be released")
        }
    }

}
