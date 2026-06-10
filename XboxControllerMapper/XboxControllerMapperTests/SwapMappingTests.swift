import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Swapping button mappings (basic, advanced features, layers, chords, macros).
/// Split from the original XboxControllerMapperTests.swift monolith.
final class SwapMappingTests: MappingEngineTestCase {

    // MARK: - Swap Mapping Tests

    /// Test swapping two button mappings in base layer
    func testSwapMappingsBasic() async throws {
        await MainActor.run {
            // Set up profile with two different mappings
            let mappingA = KeyMapping(keyCode: 0, modifiers: .command, hint: "Hint A")  // A key with Cmd
            let mappingB = KeyMapping(keyCode: 1, modifiers: .shift, hint: "Hint B")    // S key with Shift
            let profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA, .b: mappingB])
            profileManager.setActiveProfile(profile)
        }

        // Perform the swap
        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        // Verify the mappings are swapped
        await MainActor.run {
            let newMappingA = profileManager.getMapping(for: .a)
            let newMappingB = profileManager.getMapping(for: .b)

            // A should now have B's original mapping
            XCTAssertEqual(newMappingA?.keyCode, 1, "Button A should have B's keyCode after swap")
            XCTAssertTrue(newMappingA?.modifiers.shift ?? false, "Button A should have B's modifiers after swap")
            XCTAssertEqual(newMappingA?.hint, "Hint B", "Button A should have B's hint after swap")

            // B should now have A's original mapping
            XCTAssertEqual(newMappingB?.keyCode, 0, "Button B should have A's keyCode after swap")
            XCTAssertTrue(newMappingB?.modifiers.command ?? false, "Button B should have A's modifiers after swap")
            XCTAssertEqual(newMappingB?.hint, "Hint A", "Button B should have A's hint after swap")
        }
    }

    /// Test swapping when one button has mapping and other doesn't
    func testSwapMappingsOneEmpty() async throws {
        await MainActor.run {
            let mappingA = KeyMapping(keyCode: 5)
            let profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA])
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        await MainActor.run {
            let newMappingA = profileManager.getMapping(for: .a)
            let newMappingB = profileManager.getMapping(for: .b)

            // A should now be empty (B had no mapping)
            XCTAssertNil(newMappingA, "Button A should be nil after swap with empty button")

            // B should now have A's original mapping
            XCTAssertEqual(newMappingB?.keyCode, 5, "Button B should have A's keyCode after swap")
        }
    }

    /// Test swapping preserves long hold and double tap mappings
    func testSwapMappingsWithAdvancedFeatures() async throws {
        await MainActor.run {
            var mappingA = KeyMapping(keyCode: 0)
            mappingA.longHoldMapping = LongHoldMapping(keyCode: 10, threshold: 0.5)
            mappingA.doubleTapMapping = DoubleTapMapping(keyCode: 11, threshold: 0.3)

            var mappingB = KeyMapping(keyCode: 1)
            mappingB.repeatMapping = RepeatMapping(enabled: true, interval: 0.1)
            mappingB.isHoldModifier = true

            let profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA, .b: mappingB])
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        await MainActor.run {
            let newMappingA = profileManager.getMapping(for: .a)
            let newMappingB = profileManager.getMapping(for: .b)

            // A should now have B's repeat and hold settings
            XCTAssertEqual(newMappingA?.keyCode, 1)
            XCTAssertTrue(newMappingA?.repeatMapping?.enabled ?? false, "Button A should have B's repeat setting")
            XCTAssertTrue(newMappingA?.isHoldModifier ?? false, "Button A should have B's hold modifier setting")
            XCTAssertNil(newMappingA?.longHoldMapping, "Button A should not have long hold (B didn't have it)")

            // B should now have A's long hold and double tap
            XCTAssertEqual(newMappingB?.keyCode, 0)
            XCTAssertEqual(newMappingB?.longHoldMapping?.keyCode, 10, "Button B should have A's long hold mapping")
            XCTAssertEqual(newMappingB?.doubleTapMapping?.keyCode, 11, "Button B should have A's double tap mapping")
        }
    }

    /// Test swapping same button with itself does nothing
    func testSwapMappingsSameButton() async throws {
        await MainActor.run {
            let mappingA = KeyMapping(keyCode: 5, hint: "Original")
            let profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA])
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .a)
        }

        await MainActor.run {
            let mapping = profileManager.getMapping(for: .a)
            XCTAssertEqual(mapping?.keyCode, 5, "Mapping should be unchanged when swapping with self")
            XCTAssertEqual(mapping?.hint, "Original", "Hint should be unchanged when swapping with self")
        }
    }

    /// Test swapping within a layer
    func testSwapLayerMappings() async throws {
        await MainActor.run {
            var profile = Profile(name: "Layer Swap Test")

            // Create a layer with button mappings
            var layer = Layer(id: UUID(), name: "Test Layer", activatorButton: .leftBumper)
            layer.buttonMappings[.a] = KeyMapping(keyCode: 10, hint: "Layer A")
            layer.buttonMappings[.b] = KeyMapping(keyCode: 11, hint: "Layer B")
            profile.layers.append(layer)

            profileManager.setActiveProfile(profile)
        }

        // Get the layer ID
        var layerId: UUID!
        await MainActor.run {
            layerId = profileManager.activeProfile?.layers.first?.id
        }

        // Swap within the layer
        await MainActor.run {
            profileManager.swapLayerMappings(button1: .a, button2: .b, in: layerId)
        }

        // Verify the swap
        await MainActor.run {
            guard let layer = profileManager.activeProfile?.layers.first else {
                XCTFail("Layer should exist")
                return
            }

            let newMappingA = layer.buttonMappings[.a]
            let newMappingB = layer.buttonMappings[.b]

            XCTAssertEqual(newMappingA?.keyCode, 11, "Layer button A should have B's keyCode")
            XCTAssertEqual(newMappingA?.hint, "Layer B", "Layer button A should have B's hint")
            XCTAssertEqual(newMappingB?.keyCode, 10, "Layer button B should have A's keyCode")
            XCTAssertEqual(newMappingB?.hint, "Layer A", "Layer button B should have A's hint")
        }
    }

    /// Test that swapping does not affect chords
    func testSwapMappingsDoesNotAffectChords() async throws {
        await MainActor.run {
            let mappingA = KeyMapping(keyCode: 0)
            let mappingB = KeyMapping(keyCode: 1)
            let chord = ChordMapping(buttons: [.a, .b], keyCode: 99, hint: "Chord AB")

            var profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA, .b: mappingB])
            profile.chordMappings.append(chord)
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        await MainActor.run {
            // Chord should be unchanged
            guard let profile = profileManager.activeProfile else {
                XCTFail("Profile should exist")
                return
            }

            XCTAssertEqual(profile.chordMappings.count, 1, "Chord count should be unchanged")
            let chord = profile.chordMappings.first
            XCTAssertEqual(chord?.buttons, [.a, .b], "Chord buttons should be unchanged")
            XCTAssertEqual(chord?.keyCode, 99, "Chord keyCode should be unchanged")
            XCTAssertEqual(chord?.hint, "Chord AB", "Chord hint should be unchanged")
        }
    }

    /// Test swapping with macro assignments
    func testSwapMappingsWithMacros() async throws {
        let macroId1 = UUID()
        let macroId2 = UUID()

        await MainActor.run {
            var profile = Profile(name: "Macro Swap Test")
            profile.macros = [
                Macro(id: macroId1, name: "Macro 1", steps: [.delay(0.1)]),
                Macro(id: macroId2, name: "Macro 2", steps: [.delay(0.2)])
            ]
            profile.buttonMappings[.a] = KeyMapping(macroId: macroId1, hint: "Triggers Macro 1")
            profile.buttonMappings[.b] = KeyMapping(macroId: macroId2, hint: "Triggers Macro 2")
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        await MainActor.run {
            let newMappingA = profileManager.getMapping(for: .a)
            let newMappingB = profileManager.getMapping(for: .b)

            XCTAssertEqual(newMappingA?.macroId, macroId2, "Button A should have B's macro")
            XCTAssertEqual(newMappingA?.hint, "Triggers Macro 2", "Button A should have B's hint")
            XCTAssertEqual(newMappingB?.macroId, macroId1, "Button B should have A's macro")
            XCTAssertEqual(newMappingB?.hint, "Triggers Macro 1", "Button B should have A's hint")
        }
    }

}
