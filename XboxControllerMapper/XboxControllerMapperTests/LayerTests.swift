import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

/// Layer activation, layer mappings, fallthrough, multiple layers, and layer state lifecycle.
/// Split from the original XboxControllerMapperTests.swift monolith.
final class LayerTests: MappingEngineTestCase {

    // MARK: - Layer Tests

    /// Test that consecutive button presses work correctly (no layers configured)
    func testConsecutiveButtonPressesWithoutLayers() async throws {
        await MainActor.run {
            // Set up profile with mappings for Y and A buttons, no layers
            let yMapping = KeyMapping(keyCode: 16)  // Y key
            let aMapping = KeyMapping(keyCode: 0)   // A key
            let profile = Profile(name: "Test", buttonMappings: [.y: yMapping, .a: aMapping])
            profileManager.setActiveProfile(profile)
        }
        // Allow Combine to deliver profile change
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // Press and release Y button
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.2)

        // Verify Y mapping executed
        var foundYPress = false
        await MainActor.run {
            foundYPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 16 }
                return false
            }
        }
        XCTAssertTrue(foundYPress, "Y button mapping should have executed")

        // Now press and release A button
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)

        // Verify A mapping also executed
        var foundAPress = false
        await MainActor.run {
            foundAPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                return false
            }
        }
        XCTAssertTrue(foundAPress, "A button mapping should have executed after Y button")
    }

    /// Test that layer activator buttons activate layers
    func testLayerActivatorActivatesLayer() async throws {
        await MainActor.run {
            // Create a layer with LB as activator
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [:])
            let profile = Profile(name: "Test", buttonMappings: [:], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        // Allow Combine to deliver profile change
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // Press LB (layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.2)

        // LB should NOT produce any key press (it's just activating the layer)
        var foundKeyPress = false
        await MainActor.run {
            foundKeyPress = mockInputSimulator.events.contains { event in
                if case .pressKey(_, _) = event { return true }
                return false
            }
        }
        XCTAssertFalse(foundKeyPress, "Layer activator should not produce key press")
    }

    /// Test that regular buttons still work when layers are configured
    func testRegularButtonsWorkWithLayersConfigured() async throws {
        await MainActor.run {
            // Create a layer with LB as activator
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [:])
            let yMapping = KeyMapping(keyCode: 16)  // Y key
            let profile = Profile(name: "Test", buttonMappings: [.y: yMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        // Allow Combine to deliver profile change
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // Press Y button (not a layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.2)

        // Verify Y mapping executed
        var foundYPress = false
        await MainActor.run {
            foundYPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 16 }
                return false
            }
        }
        XCTAssertTrue(foundYPress, "Y button should work even when layers are configured")
    }

    /// Test consecutive button presses with layers configured
    func testConsecutiveButtonPressesWithLayers() async throws {
        await MainActor.run {
            // Create a layer with LB as activator
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [:])
            let yMapping = KeyMapping(keyCode: 16)  // Y key
            let aMapping = KeyMapping(keyCode: 0)   // A key
            let profile = Profile(name: "Test", buttonMappings: [.y: yMapping, .a: aMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        // Allow Combine to deliver profile change
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // Press LB (layer activator) first
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.1)

        // Press Y button
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.2)

        // Verify Y mapping executed
        var foundYPress = false
        await MainActor.run {
            foundYPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 16 }
                return false
            }
        }
        XCTAssertTrue(foundYPress, "Y button mapping should work after layer activator was pressed")

        // Press A button
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)

        // Verify A mapping also executed
        var foundAPress = false
        await MainActor.run {
            foundAPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                return false
            }
        }
        XCTAssertTrue(foundAPress, "A button mapping should work after Y button")
    }

    /// Test that layer-specific mapping is used when layer activator is held
    func testLayerMappingUsedWhenLayerActive() async throws {
        await MainActor.run {
            // Base layer: Y -> key 16 (Y key)
            // Layer: Y -> key 0 (A key)
            let baseYMapping = KeyMapping(keyCode: 16)  // Y key
            let layerYMapping = KeyMapping(keyCode: 0)   // A key (different!)
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [.y: layerYMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Press and HOLD LB (layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Clear events before pressing Y
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y while LB is held - should use LAYER mapping (key 0, not 16)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        // Verify layer mapping was used (key 0), not base mapping (key 16)
        var foundLayerMapping = false
        var foundBaseMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 0 { foundLayerMapping = true }
                    if code == 16 { foundBaseMapping = true }
                }
            }
        }
        XCTAssertTrue(foundLayerMapping, "Layer mapping (key 0) should be used when layer is active")
        XCTAssertFalse(foundBaseMapping, "Base mapping (key 16) should NOT be used when layer is active")
    }

    /// Test that buttons not mapped in layer fall through to base layer
    func testLayerFallthroughToBaseLayer() async throws {
        await MainActor.run {
            // Base layer: Y -> key 16, A -> key 0
            // Layer: only has mapping for A -> key 1 (different), Y is not mapped in layer
            let baseYMapping = KeyMapping(keyCode: 16)  // Y key
            let baseAMapping = KeyMapping(keyCode: 0)   // A key
            let layerAMapping = KeyMapping(keyCode: 1)  // S key (override for A)
            // Layer has NO mapping for Y
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [.a: layerAMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping, .a: baseAMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Press and HOLD LB (layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y while layer is active - should fall through to base layer (key 16)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        // Verify Y used base layer mapping (fallthrough)
        var foundYBaseMapping = false
        await MainActor.run {
            foundYBaseMapping = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 16 }
                return false
            }
        }
        XCTAssertTrue(foundYBaseMapping, "Y should fall through to base layer mapping when not in layer")

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press A while layer is active - should use layer mapping (key 1), not base (key 0)
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.1)

        var foundALayerMapping = false
        var foundABaseMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 1 { foundALayerMapping = true }
                    if code == 0 { foundABaseMapping = true }
                }
            }
        }
        XCTAssertTrue(foundALayerMapping, "A should use layer mapping when layer is active")
        XCTAssertFalse(foundABaseMapping, "A should NOT use base mapping when layer overrides it")
    }

    /// Test that layer deactivates when activator button is released
    func testLayerDeactivatesOnRelease() async throws {
        await MainActor.run {
            // Base layer: Y -> key 16
            // Layer: Y -> key 0
            let baseYMapping = KeyMapping(keyCode: 16)
            let layerYMapping = KeyMapping(keyCode: 0)
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [.y: layerYMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Press and HOLD LB, then release it
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y after LB was released - should use BASE mapping (key 16)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundBaseMapping = false
        var foundLayerMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 16 { foundBaseMapping = true }
                    if code == 0 { foundLayerMapping = true }
                }
            }
        }
        XCTAssertTrue(foundBaseMapping, "Base mapping should be used after layer deactivates")
        XCTAssertFalse(foundLayerMapping, "Layer mapping should NOT be used after layer deactivates")
    }

    /// Test that multiple layers can be configured with different activators
    func testMultipleLayers() async throws {
        await MainActor.run {
            // Base layer: Y -> key 16
            // Layer 1 (LB): Y -> key 0
            // Layer 2 (RB): Y -> key 1
            let baseYMapping = KeyMapping(keyCode: 16)
            let layer1YMapping = KeyMapping(keyCode: 0)
            let layer2YMapping = KeyMapping(keyCode: 1)
            let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.y: layer1YMapping])
            let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.y: layer2YMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping], layers: [layer1, layer2])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Test Layer 1 activation (LB)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            mockInputSimulator.clearEvents()
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.1)

        var foundLayer1Mapping = false
        await MainActor.run {
            foundLayer1Mapping = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                return false
            }
        }
        XCTAssertTrue(foundLayer1Mapping, "Layer 1 mapping should be used when LB is held")

        // Test Layer 2 activation (RB)
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            mockInputSimulator.clearEvents()
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
            controllerService.buttonReleased(.rightBumper)
        }
        await waitForTasks(0.1)

        var foundLayer2Mapping = false
        await MainActor.run {
            foundLayer2Mapping = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }
        }
        XCTAssertTrue(foundLayer2Mapping, "Layer 2 mapping should be used when RB is held")
    }

    /// Test that layer activator button releases don't trigger any mapping
    func testLayerActivatorReleaseProducesNoOutput() async throws {
        await MainActor.run {
            // Give LB a base mapping that should NOT trigger when used as layer activator
            let lbMapping = KeyMapping(keyCode: 16)
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [:])
            let profile = Profile(name: "Test", buttonMappings: [.leftBumper: lbMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Press and release LB (layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.2)

        // Verify NO key press occurred
        var foundAnyKeyPress = false
        await MainActor.run {
            foundAnyKeyPress = mockInputSimulator.events.contains { event in
                if case .pressKey(_, _) = event { return true }
                return false
            }
        }
        XCTAssertFalse(foundAnyKeyPress, "Layer activator should not produce any key press, even if base layer has a mapping for it")
    }

    /// Test that layer state is cleared when profile switches while layer activator is held
    func testLayerStateClearedOnProfileSwitch() async throws {
        // Profile A: LB activates layer, Y -> key 0 in layer
        // Profile B: No layers, Y -> key 16 in base
        let layerAYMapping = KeyMapping(keyCode: 0)
        let layerA = Layer(name: "Layer A", activatorButton: .leftBumper, buttonMappings: [.y: layerAYMapping])
        let profileA = Profile(name: "Profile A", buttonMappings: [:], layers: [layerA])

        let baseBYMapping = KeyMapping(keyCode: 16)
        let profileB = Profile(name: "Profile B", buttonMappings: [.y: baseBYMapping], layers: [])

        await MainActor.run {
            profileManager.setActiveProfile(profileA)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Hold LB to activate layer in Profile A
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Switch to Profile B while LB is still held
        await MainActor.run {
            profileManager.setActiveProfile(profileB)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y - should use Profile B's base mapping (key 16), not stale layer mapping
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundProfileBMapping = false
        var foundStaleLayerMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 16 { foundProfileBMapping = true }
                    if code == 0 { foundStaleLayerMapping = true }
                }
            }
        }
        XCTAssertTrue(foundProfileBMapping, "Profile B's base mapping should be used after profile switch")
        XCTAssertFalse(foundStaleLayerMapping, "Stale layer mapping from Profile A should NOT be used")
    }

    /// Test that pressing another layer activator while a layer is active does not steal priority
    func testSecondLayerActivatorDoesNotStealPriority() async throws {
        await MainActor.run {
            // Layer 1 (LB): Y -> key 0
            // Layer 2 (RB): Y -> key 1
            let layer1YMapping = KeyMapping(keyCode: 0)
            let layer2YMapping = KeyMapping(keyCode: 1)
            let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.y: layer1YMapping])
            let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.y: layer2YMapping])
            let profile = Profile(name: "Test", buttonMappings: [:], layers: [layer1, layer2])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Hold LB (Layer 1)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Now also press RB (Layer 2). While Layer 1 is active, RB is treated as
        // a remappable button in Layer 1 rather than a global layer switch.
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y - should keep using Layer 1's mapping (key 0), not Layer 2's (key 1)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundLayer2Mapping = false
        var foundLayer1Mapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 1 { foundLayer2Mapping = true }
                    if code == 0 { foundLayer1Mapping = true }
                }
            }
        }
        XCTAssertTrue(foundLayer1Mapping, "Layer 1 mapping should remain active")
        XCTAssertFalse(foundLayer2Mapping, "Layer 2 mapping should NOT be used while Layer 1 is active")
    }

    /// Test that releasing the most recent layer activator reverts to the previous held layer
    func testLayerSwitchingReleaseRevertsToHeldLayer() async throws {
        await MainActor.run {
            // Base: Y -> key 16
            // Layer 1 (LB): Y -> key 0
            // Layer 2 (RB): Y -> key 1
            let baseYMapping = KeyMapping(keyCode: 16)
            let layer1YMapping = KeyMapping(keyCode: 0)
            let layer2YMapping = KeyMapping(keyCode: 1)
            let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.y: layer1YMapping])
            let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.y: layer2YMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping], layers: [layer1, layer2])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Hold LB (Layer 1), then press RB (Layer 2)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)

        // Now release RB - should revert to Layer 1 (LB still held)
        await MainActor.run {
            controllerService.buttonReleased(.rightBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y - should use Layer 1's mapping (key 0)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundLayer1Mapping = false
        var foundLayer2Mapping = false
        var foundBaseMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 0 { foundLayer1Mapping = true }
                    if code == 1 { foundLayer2Mapping = true }
                    if code == 16 { foundBaseMapping = true }
                }
            }
        }
        XCTAssertTrue(foundLayer1Mapping, "Layer 1 mapping should be used after releasing Layer 2")
        XCTAssertFalse(foundLayer2Mapping, "Layer 2 mapping should NOT be used after releasing it")
        XCTAssertFalse(foundBaseMapping, "Base mapping should NOT be used while Layer 1 activator is held")
    }

    /// Test that another layer's activator is remappable while the current layer is active
    func testLayerActivatorWithoutRemapDoesNotSwitchFromActiveLayer() async throws {
        await MainActor.run {
            // Layer 1 (LB): Y -> key 0
            // Layer 2 (RB): Y -> key 1
            let layer1YMapping = KeyMapping(keyCode: 0)
            let layer2YMapping = KeyMapping(keyCode: 1)
            let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.y: layer1YMapping])
            let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.y: layer2YMapping])
            let profile = Profile(name: "Test", buttonMappings: [:], layers: [layer1, layer2])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Hold LB (enter Layer 1)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press RB while in Layer 1. Because Layer 1 has no RB mapping, this should not
        // produce key output and should not switch away from Layer 1.
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)

        // Verify no key was pressed for RB (it's a layer activator)
        var foundAnyKeyPress = false
        await MainActor.run {
            foundAnyKeyPress = mockInputSimulator.events.contains { event in
                if case .pressKey(_, _) = event { return true }
                return false
            }
        }
        XCTAssertFalse(foundAnyKeyPress, "Unmapped RB should not produce a key press")

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y - should still use Layer 1's mapping
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundLayer1Mapping = false
        var foundLayer2Mapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 0 { foundLayer1Mapping = true }
                    if code == 1 { foundLayer2Mapping = true }
                }
            }
        }
        XCTAssertTrue(foundLayer1Mapping, "Layer 1 mapping should remain active")
        XCTAssertFalse(foundLayer2Mapping, "Layer 2 mapping should NOT be used while Layer 1 is active")
    }

}
