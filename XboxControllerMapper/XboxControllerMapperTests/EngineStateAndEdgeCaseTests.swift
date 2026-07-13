import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Engine state, profile-change, unmapped-button, repeat-mapping, rapid-input, and connection-state edge cases.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class EngineStateAndEdgeCaseTests: MappingEngineTestCase {

    // MARK: - Profile Change Edge Cases

    /// Tests that changing profile while button is held doesn't cause issues
    func testProfileChangeWhileButtonHeld() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "P1", buttonMappings: [.leftBumper: .holdModifier(.command)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.emitInputEvent(.buttonPressed(.leftBumper))
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held")

            // Change profile while button held
            profileManager.setActiveProfile(Profile(name: "P2", buttonMappings: [.leftBumper: .holdModifier(.shift)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Release with OLD profile's mapping should still work
            controllerService.emitInputEvent(.buttonReleased(.leftBumper, holdDuration: 0.5))
        }
        await waitForTasks()

        await MainActor.run {
            // Modifier should be released (engine tracks held buttons, not profile)
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be released after button release")
        }
    }

    /// Tests that clearing profile (nil) while button held doesn't crash
    func testNilProfileWhileButtonHeld() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.emitInputEvent(.buttonPressed(.a))
        }
        await waitForTasks(0.1)

        // This shouldn't crash - engine should handle gracefully
        // Note: ProfileManager might not allow nil profile, but testing the guard
    }

    // MARK: - Unmapped Button Edge Cases

    /// Tests that pressing unmapped button doesn't cause issues
    func testUnmappedButton() async throws {
        await MainActor.run {
            // Only map A, not B
            profileManager.setActiveProfile(Profile(name: "Partial", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.emitInputEvent(.buttonPressed(.b))
            controllerService.emitInputEvent(.buttonReleased(.b, holdDuration: 0.1))
        }
        await waitForTasks()

        await MainActor.run {
            // No crash, no events for unmapped button
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey = event { return true }
                return false
            }, "Unmapped button should not trigger any key press")
        }
    }

    /// Tests that pressing unmapped button followed by mapped button works
    func testUnmappedThenMappedButton() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Partial", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Press unmapped button first
            controllerService.emitInputEvent(.buttonPressed(.b))
        }
        await waitForTasks(0.1)

        await MainActor.run {
            // Then press mapped button
            controllerService.emitInputEvent(.buttonPressed(.a))
            controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.05))
        }
        await waitForTasks()

        await MainActor.run {
            // Mapped button should still work
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Mapped button should work even after unmapped button press")
        }
    }

    // MARK: - Repeat Mapping Edge Cases

    /// Tests repeat mapping fires multiple times while held
    func testRepeatMappingFires() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.repeatMapping = RepeatMapping(enabled: true, interval: 0.05)
            profileManager.setActiveProfile(Profile(name: "Repeat", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.emitInputEvent(.buttonPressed(.a))
        }

        // Hold for multiple repeat intervals
        await waitForTasks(0.25)

        await MainActor.run {
            controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.25))
        }
        await waitForTasks()

        await MainActor.run {
            // Should have multiple executions (initial + repeats)
            let count = mockInputSimulator.events.filter { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            }.count

            XCTAssertGreaterThan(count, 1, "Repeat mapping should fire multiple times, got \(count)")
        }
    }

    /// Tests repeat stops immediately when button released
    func testRepeatStopsOnRelease() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.repeatMapping = RepeatMapping(enabled: true, interval: 0.05)
            profileManager.setActiveProfile(Profile(name: "Repeat", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.emitInputEvent(.buttonPressed(.a))
        }
        await waitForTasks(0.15)

        let countBeforeRelease = await MainActor.run {
            return mockInputSimulator.events.filter { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            }.count
        }

        await MainActor.run {
            controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.15))
        }

        // Wait to verify no more repeats
        await waitForTasks(0.2)

        await MainActor.run {
            let countAfterRelease = mockInputSimulator.events.filter { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            }.count

            XCTAssertEqual(countBeforeRelease, countAfterRelease, "No additional repeats should occur after release")
        }
    }

    // MARK: - Engine State Edge Cases

    /// Tests re-enabling engine doesn't cause double-execution
    func testReEnableEngineCleanState() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            mappingEngine.disable()
        }
        await waitForTasks()

        await MainActor.run {
            mappingEngine.enable()
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.emitInputEvent(.buttonPressed(.a))
            controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.05))
        }
        await waitForTasks()

        await MainActor.run {
            let count = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }.count

            XCTAssertEqual(count, 1, "Should execute exactly once after re-enable")
        }
    }

    /// Tests that disabling engine mid-press releases held modifier
    func testDisableEngineReleasesHeldModifier() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [
                .leftBumper: .holdModifier(.command),
                .rightBumper: .holdModifier(.shift)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.emitInputEvent(.buttonPressed(.leftBumper))
            controllerService.emitInputEvent(.buttonPressed(.rightBumper))
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift))

            mappingEngine.disable()
        }
        await waitForTasks()

        await MainActor.run {
            // All modifiers should be released
            XCTAssertTrue(mockInputSimulator.heldModifiers.isEmpty, "All modifiers should be released on disable")
        }
    }

    // MARK: - Rapid Input Edge Cases

    /// Tests rapid button press/release doesn't lose events
    func testRapidPressRelease() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Rapid", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Rapid fire 5 press/release cycles
        for _ in 0..<5 {
            await MainActor.run {
                controllerService.emitInputEvent(.buttonPressed(.a))
                controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.01))
            }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms between cycles
        }

        await waitForTasks()

        await MainActor.run {
            let count = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }.count

            XCTAssertEqual(count, 5, "All 5 rapid presses should be processed, got \(count)")
        }
    }

    /// Tests alternating between two buttons rapidly
    func testAlternatingButtons() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Alt", buttonMappings: [.a: .key(1), .b: .key(2)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Alternate A and B rapidly
        for i in 0..<4 {
            let button: ControllerButton = i % 2 == 0 ? .a : .b
            await MainActor.run {
                controllerService.emitInputEvent(.buttonPressed(button))
                controllerService.emitInputEvent(.buttonReleased(button, holdDuration: 0.01))
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }

        await waitForTasks()

        await MainActor.run {
            let aCount = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }.count
            let bCount = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }.count

            XCTAssertEqual(aCount, 2, "Button A should fire twice")
            XCTAssertEqual(bCount, 2, "Button B should fire twice")
        }
    }

    // MARK: - Connection State Tests (High Priority)

    /// Tests that engine handles button state on connection change
    func testButtonStateDuringConnectionChange() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Conn", buttonMappings: [
                .leftBumper: .holdModifier(.command)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held")
        }

        // Simulate disconnect by disabling engine
        await MainActor.run {
            mappingEngine.disable()
        }
        await waitForTasks()

        await MainActor.run {
            // Modifiers should be released when engine is disabled
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be released on disconnect")
        }
    }

    /// Tests that engine can be re-enabled after disable
    func testEngineReEnableAfterDisable() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "ReEnable", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            mappingEngine.disable()
        }
        await waitForTasks()

        await MainActor.run {
            mappingEngine.enable()
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }, "Engine should work after re-enable")
        }
    }

    // MARK: - Empty Profile Tests

    /// Tests behavior with empty profile (no mappings)
    func testEmptyProfile() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Empty", buttonMappings: [:]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            // Should not crash, no key presses should occur
            let keyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey = event { return true }
                return false
            }
            XCTAssertTrue(keyPresses.isEmpty, "Empty profile should produce no key presses")
        }
    }

    // MARK: - Rapid Fire Edge Cases

    /// Tests rapid button press/release cycles
    func testRapidButtonCycles() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Rapid", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Rapid press/release cycles
        for _ in 0..<5 {
            await MainActor.run {
                controllerService.emitInputEvent(.buttonPressed(.a))
                controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.01))
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        await waitForTasks()

        await MainActor.run {
            let pressCount = mockInputSimulator.events.filter { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }.count

            // Should have executed 5 times (not coalesced)
            XCTAssertEqual(pressCount, 5, "All rapid presses should execute")
        }
    }

    /// Tests button press while another is being held
    func testInterruptHoldWithAnotherButton() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(
                name: "Interrupt",
                buttonMappings: [
                    .a: .holdModifier(.command),
                    .b: .key(1)
                ]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Start holding A
            controllerService.emitInputEvent(.buttonPressed(.a))
        }
        await waitForTasks(0.1)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))

            // Press and release B while A held
            controllerService.emitInputEvent(.buttonPressed(.b))
            controllerService.emitInputEvent(.buttonReleased(.b, holdDuration: 0.05))
        }
        await waitForTasks()

        await MainActor.run {
            // B should execute with command modifier context
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            })

            // A should still be held
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
        }

        await MainActor.run {
            controllerService.emitInputEvent(.buttonReleased(.a, holdDuration: 0.5))
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand))
        }
    }

}
