import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Macro execution (multi-step, type-text, on chord), system commands, and macro management on the profile.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class MacroEngineTests: MappingEngineTestCase {

    // MARK: - Macro Execution Tests (High Priority)

    /// Tests that macro with multiple steps executes correctly
    func testMacroWithMultipleSteps() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(
                id: macroId,
                name: "Test Macro",
                steps: [
                    .press(KeyMapping(keyCode: 0)), // 'a' key
                    .press(KeyMapping(keyCode: 1)), // 's' key
                    .press(KeyMapping(keyCode: 2))  // 'd' key
                ]
            )
            var profile = Profile(name: "MacroTest", buttonMappings: [:])
            profile.macros = [macro]
            profile.buttonMappings[.a] = KeyMapping(macroId: macroId)
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            // The mock's executeMacro simulates all steps
            let pressEvents = mockInputSimulator.events.filter { event in
                if case .pressKey = event { return true }
                return false
            }
            XCTAssertEqual(pressEvents.count, 3, "Macro should execute all 3 steps")
        }
    }

    /// Tests that macro with typeText step executes correctly
    /// Note: The actual typing uses nil CGEventSource to prevent held modifiers from affecting text
    func testMacroWithTypeTextStep() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(
                id: macroId,
                name: "Type Macro",
                steps: [
                    .typeText("hello@example.com", speed: 300)
                ]
            )
            var profile = Profile(name: "TypeTest", buttonMappings: [:])
            profile.macros = [macro]
            profile.buttonMappings[.a] = KeyMapping(macroId: macroId)
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            let typeEvents = mockInputSimulator.events.filter { event in
                if case .typeText = event { return true }
                return false
            }
            XCTAssertEqual(typeEvents.count, 1, "Macro should execute typeText step")

            if case .typeText(let text, let speed, _) = typeEvents.first {
                XCTAssertEqual(text, "hello@example.com", "Text should match")
                XCTAssertEqual(speed, 300, "Speed should match")
            }
        }
    }

    /// Tests that macro typeText works while modifiers are held (simulates on-screen keyboard scenario)
    /// The fix ensures typed characters use nil CGEventSource to avoid inheriting held modifier state
    func testMacroTypeTextIgnoresHeldModifiers() async throws {
        let macroId = UUID()

        await MainActor.run {
            // Hold a modifier (simulating on-screen keyboard button)
            mockInputSimulator.holdModifier(.maskCommand)

            let macro = Macro(
                id: macroId,
                name: "Type While Modifier Held",
                steps: [
                    .typeText("test@123", speed: 300)
                ]
            )
            var profile = Profile(name: "ModifierTest", buttonMappings: [:])
            profile.macros = [macro]
            profile.buttonMappings[.b] = KeyMapping(macroId: macroId)
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Verify modifier is held
            XCTAssertTrue(mockInputSimulator.isHoldingModifiers(.maskCommand), "Modifier should be held")

            controllerService.buttonPressed(.b)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        await MainActor.run {
            // TypeText event should be recorded regardless of held modifiers
            let typeEvents = mockInputSimulator.events.filter { event in
                if case .typeText = event { return true }
                return false
            }
            XCTAssertEqual(typeEvents.count, 1, "TypeText should execute even with modifier held")

            // The actual CGEvent implementation uses nil source to prevent modifier inheritance
            // This test documents the expected behavior - the mock doesn't simulate CGEvent details
            if case .typeText(let text, _, _) = typeEvents.first {
                XCTAssertEqual(text, "test@123", "Text content should be preserved")
            }
        }
    }

    /// Tests that macro can be assigned to chord
    func testMacroOnChord() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(
                id: macroId,
                name: "Chord Macro",
                steps: [
                    .press(KeyMapping(keyCode: 5)),
                    .press(KeyMapping(keyCode: 6))
                ]
            )
            var profile = Profile(name: "ChordMacro", buttonMappings: [:])
            profile.macros = [macro]
            profile.chordMappings = [ChordMapping(buttons: [.a, .b], macroId: macroId)]
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.emitInputEvent(.chordDetected([.a, .b]))
        }
        await waitForTasks()

        await MainActor.run {
            let pressEvents = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 5 || code == 6 }
                return false
            }
            XCTAssertEqual(pressEvents.count, 2, "Chord should trigger macro with 2 steps")
        }
    }

    // MARK: - System Command Tests (Medium Priority)

    /// Tests that system command mapping is recognized
    func testSystemCommandMapping() async throws {
        await MainActor.run {
            let mapping = KeyMapping(systemCommand: .shellCommand(command: "echo test", inTerminal: false))
            profileManager.setActiveProfile(Profile(name: "SysCmd", buttonMappings: [.menu: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Verify the mapping was set up correctly
        await MainActor.run {
            let profile = profileManager.activeProfile
            XCTAssertNotNil(profile?.buttonMappings[.menu]?.systemCommand, "System command should be set")
        }
    }

    // MARK: - Macro Management Tests

    /// Tests adding a macro to profile
    func testAddMacro() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            let macro = Macro(name: "TestMacro", steps: [.press(KeyMapping(keyCode: 1))])
            profileManager.addMacro(macro)

            XCTAssertEqual(profileManager.activeProfile?.macros.count, 1)
            XCTAssertEqual(profileManager.activeProfile?.macros.first?.name, "TestMacro")
        }
    }

    /// Tests removing a macro also unmaps it from buttons
    func testRemoveMacroUnmapsFromButtons() async throws {
        await MainActor.run {
            let macro = Macro(name: "TestMacro", steps: [.press(KeyMapping(keyCode: 1))])

            var buttonMapping = KeyMapping()
            buttonMapping.macroId = macro.id

            let profile = Profile(
                name: "Test",
                buttonMappings: [.a: buttonMapping],
                macros: [macro]
            )
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            // Verify initial state
            XCTAssertEqual(profileManager.activeProfile?.buttonMappings[.a]?.macroId, macro.id)

            profileManager.removeMacro(macro)

            // Macro should be removed
            XCTAssertEqual(profileManager.activeProfile?.macros.count, 0)
            // Button mapping should be removed too
            XCTAssertNil(profileManager.activeProfile?.buttonMappings[.a])
        }
    }

    /// Tests updating a macro
    func testUpdateMacro() async throws {
        await MainActor.run {
            let macro = Macro(name: "Original", steps: [.press(KeyMapping(keyCode: 1))])
            let profile = Profile(name: "Test", macros: [macro])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            var updatedMacro = macro
            updatedMacro.name = "Updated"
            updatedMacro.steps = [.press(KeyMapping(keyCode: 2)), .delay(0.1)]

            profileManager.updateMacro(updatedMacro)

            XCTAssertEqual(profileManager.activeProfile?.macros.first?.name, "Updated")
            XCTAssertEqual(profileManager.activeProfile?.macros.first?.steps.count, 2)
        }
    }

}
