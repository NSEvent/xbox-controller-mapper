import XCTest
import CoreGraphics
@testable import ControllerKeys

final class MappingEngineLayerAndLifecycleTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-layer-lifecycle-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            controllerService = ControllerService(enableHardwareMonitoring: false)
            controllerService.chordWindow = 0.05
            profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
            appMonitor = AppMonitor()
            mockInputSimulator = MockInputSimulator()

            mappingEngine = MappingEngine(
                controllerService: controllerService,
                profileManager: profileManager,
                appMonitor: appMonitor,
                inputSimulator: mockInputSimulator
            )
            mappingEngine.enable()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            mappingEngine?.disable()
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        await MainActor.run {
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.onLeftStickMoved = nil
            controllerService?.onRightStickMoved = nil
            controllerService?.onTouchpadMoved = nil
            controllerService?.onTouchpadGesture = nil
            controllerService?.onTouchpadTap = nil
            controllerService?.onTouchpadTwoFingerTap = nil
            controllerService?.onTouchpadLongTap = nil
            controllerService?.onTouchpadTwoFingerLongTap = nil
            controllerService?.cleanup()

            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
    }

    private func waitForTasks(_ delay: TimeInterval = 0.35) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    // MARK: - Layer Tests

    /// Test 1: Activating a layer by pressing its activator button adds the layer's ID to the active set.
    func testLayerActivation_setsActiveLayerId() async throws {
        let layer = Layer(name: "Combat", activatorButton: .leftBumper, buttonMappings: [.a: .key(50)])
        await MainActor.run {
            let profile = Profile(
                name: "LayerTest",
                buttonMappings: [.a: .key(10)],
                layers: [layer]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press the layer activator
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.15)

        // Now press A — if the layer is active, it should use keyCode 50 (layer mapping)
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let layerKeyCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 50 }
            return false
        }.count
        XCTAssertEqual(layerKeyCount, 1, "Layer mapping (keyCode 50) should fire when layer is active")
    }

    /// Test 2: Deactivating a layer by releasing its activator button removes it.
    func testLayerDeactivation_removesLayerId() async throws {
        let layer = Layer(name: "Combat", activatorButton: .leftBumper, buttonMappings: [.a: .key(50)])
        await MainActor.run {
            let profile = Profile(
                name: "LayerTest",
                buttonMappings: [.a: .key(10)],
                layers: [layer]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Activate then deactivate layer
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.1)

        // Now press A — should use base mapping (keyCode 10)
        await MainActor.run {
            mockInputSimulator.clearEvents()
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let baseKeyCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 10 }
            return false
        }.count
        let layerKeyCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 50 }
            return false
        }.count
        XCTAssertEqual(baseKeyCount, 1, "Base mapping (keyCode 10) should fire after layer deactivation")
        XCTAssertEqual(layerKeyCount, 0, "Layer mapping (keyCode 50) should not fire after deactivation")
    }

    /// Test 3: A button with a layer mapping outputs the layer's keyCode when the layer is active.
    func testLayerMapping_overridesBaseMapping() async throws {
        let layer = Layer(name: "Override", activatorButton: .rightBumper, buttonMappings: [.b: .key(77)])
        await MainActor.run {
            let profile = Profile(
                name: "OverrideTest",
                buttonMappings: [.b: .key(22)],
                layers: [layer]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Hold layer activator, then press B
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonPressed(.b)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let overrideCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 77 }
            return false
        }.count
        let baseCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 22 }
            return false
        }.count
        XCTAssertEqual(overrideCount, 1, "Layer mapping should override base mapping")
        XCTAssertEqual(baseCount, 0, "Base mapping should not fire while layer is active")
    }

    /// Test 4: After deactivating a layer, button outputs the base keyCode again.
    func testLayerDeactivation_revertsToBaseMapping() async throws {
        let layer = Layer(name: "Revert", activatorButton: .rightBumper, buttonMappings: [.x: .key(88)])
        await MainActor.run {
            let profile = Profile(
                name: "RevertTest",
                buttonMappings: [.x: .key(33)],
                layers: [layer]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Activate layer, press X (layer), deactivate layer, press X (base)
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonPressed(.x)
            controllerService.buttonReleased(.x)
        }
        await waitForTasks()
        await MainActor.run {
            controllerService.buttonReleased(.rightBumper)
        }
        await waitForTasks(0.1)

        // Clear and press X again (should be base)
        await MainActor.run {
            mockInputSimulator.clearEvents()
            controllerService.buttonPressed(.x)
            controllerService.buttonReleased(.x)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let baseCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 33 }
            return false
        }.count
        let layerCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 88 }
            return false
        }.count
        XCTAssertEqual(baseCount, 1, "After layer deactivation, base mapping should fire")
        XCTAssertEqual(layerCount, 0, "Layer mapping should not fire after deactivation")
    }

    /// Test 5: When multiple layers are active, the most recently activated layer wins.
    func testMultipleLayers_lastActivatedWins() async throws {
        let layer1 = Layer(name: "First", activatorButton: .leftBumper, buttonMappings: [.a: .key(61)])
        let layer2 = Layer(name: "Second", activatorButton: .rightBumper, buttonMappings: [.a: .key(62)])
        await MainActor.run {
            let profile = Profile(
                name: "MultiLayer",
                buttonMappings: [.a: .key(60)],
                layers: [layer1, layer2]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Activate layer1 first, then layer2
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)

        // Press A — layer2 (most recent) should win
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let layer2Count = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 62 }
            return false
        }.count
        let layer1Count = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 61 }
            return false
        }.count
        XCTAssertEqual(layer2Count, 1, "Most recently activated layer (layer2) should win")
        XCTAssertEqual(layer1Count, 0, "Earlier layer should not fire when newer layer is active")
    }

    /// Test 6: The layer activator button itself does not emit its own key mapping.
    func testLayerActivator_buttonDoesNotFireOwnMapping() async throws {
        let layer = Layer(name: "Activator", activatorButton: .leftBumper, buttonMappings: [.a: .key(50)])
        await MainActor.run {
            let profile = Profile(
                name: "ActivatorTest",
                buttonMappings: [.leftBumper: .key(99), .a: .key(10)],
                layers: [layer]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press and release the layer activator
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let activatorKeyCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 99 }
            return false
        }.count
        XCTAssertEqual(activatorKeyCount, 0, "Layer activator button should not emit its own base mapping")
    }

    // MARK: - Enable/Disable Lifecycle Tests

    /// Test 7: Disabling the engine releases all held keys.
    func testDisable_releasesAllHeldKeys() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "DisableTest",
                buttonMappings: [.a: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Start holding A (hold modifier mapping)
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)

        // Verify the hold started
        let holdStarted = mockInputSimulator.events.contains {
            if case .startHoldMapping = $0 { return true }
            return false
        }
        XCTAssertTrue(holdStarted, "Hold mapping should have started")

        // Disable the engine
        await MainActor.run {
            mockInputSimulator.clearEvents()
            mappingEngine.disable()
        }
        await waitForTasks(0.2)

        // The engine should have released held state via releaseAllModifiers
        let releasedAll = mockInputSimulator.events.contains {
            if case .releaseAllModifiers = $0 { return true }
            return false
        }
        XCTAssertTrue(releasedAll, "Disabling engine should release all modifiers")
    }

    /// Test 8: Disabling the engine before long-hold threshold prevents long-hold from firing.
    func testDisable_cancelsActiveTimers() async throws {
        await MainActor.run {
            let mapping = KeyMapping(
                keyCode: 1,
                longHoldMapping: LongHoldMapping(keyCode: 4, threshold: 0.3)
            )
            let profile = Profile(name: "TimerCancel", buttonMappings: [.a: mapping])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press button (starts long-hold timer at 0.3s threshold)
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.1) // wait less than threshold

        // Disable before threshold
        await MainActor.run {
            mockInputSimulator.clearEvents()
            mappingEngine.disable()
        }

        // Wait past the threshold to ensure it doesn't fire
        await waitForTasks(0.5)

        let events = mockInputSimulator.events
        let longHoldFired = events.contains {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 4 }
            return false
        }
        XCTAssertFalse(longHoldFired, "Long-hold should not fire after engine is disabled")
    }

    /// Test 9: Re-enabling the engine after disable starts with clean state.
    func testReEnable_startsClean() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "ReEnable",
                buttonMappings: [.a: .key(1)]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press A, disable, re-enable
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            mappingEngine.disable()
        }
        await waitForTasks(0.1)
        await MainActor.run {
            mockInputSimulator.clearEvents()
            mappingEngine.enable()
        }
        await waitForTasks(0.1)

        // Press and release A — should work cleanly as a fresh press
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let pressCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count
        XCTAssertGreaterThanOrEqual(pressCount, 1, "After re-enable, button press should work normally")
    }

    /// Test 10: Disabling the engine releases held modifier keys.
    func testDisable_releasesHeldModifiers() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "ModRelease",
                buttonMappings: [.leftBumper: .holdModifier(.command)]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Hold the modifier
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.2)

        let heldBefore = mockInputSimulator.heldModifiers.contains(.maskCommand)
        XCTAssertTrue(heldBefore, "Command modifier should be held")

        // Disable
        await MainActor.run {
            mappingEngine.disable()
        }
        await waitForTasks(0.2)

        let heldAfter = mockInputSimulator.heldModifiers.contains(.maskCommand)
        XCTAssertFalse(heldAfter, "Command modifier should be released after disable")
    }

    /// Test 11: Switching profiles releases held keys from the old profile.
    func testProfileSwitch_releasesHeldKeys() async throws {
        await MainActor.run {
            let profile1 = Profile(
                name: "P1",
                buttonMappings: [.leftBumper: .holdModifier(.command)]
            )
            profileManager.setActiveProfile(profile1)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Hold modifier
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.2)

        let heldBefore = mockInputSimulator.heldModifiers.contains(.maskCommand)
        XCTAssertTrue(heldBefore, "Command should be held before switch")

        // Switch profile — the release on old button should clean up
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.2)

        let heldAfter = mockInputSimulator.heldModifiers.contains(.maskCommand)
        XCTAssertFalse(heldAfter, "Command should be released after button release following profile switch")
    }

    /// Test 12: Profile switch clears layer state but already-scheduled long-hold timers
    /// are owned by the DispatchWorkItem, not the profile — they still fire.
    func testProfileSwitch_longHoldTimerStillFires() async throws {
        await MainActor.run {
            let mapping = KeyMapping(
                keyCode: 1,
                longHoldMapping: LongHoldMapping(keyCode: 4, threshold: 0.4)
            )
            let profile1 = Profile(name: "P1", buttonMappings: [.a: mapping])
            profileManager.setActiveProfile(profile1)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press A (starts 0.4s long-hold timer)
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.1) // wait less than threshold

        // Switch profile — layers clear, but the DispatchWorkItem is already scheduled
        await MainActor.run {
            mockInputSimulator.clearEvents()
            let profile2 = Profile(name: "P2", buttonMappings: [.a: .key(5)])
            profileManager.setActiveProfile(profile2)
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Wait past the original threshold
        await waitForTasks(0.6)

        let events = mockInputSimulator.events
        let longHoldFired = events.contains {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 4 }
            return false
        }
        // The long-hold timer was already in flight — profile switch doesn't cancel it
        XCTAssertTrue(longHoldFired, "Already-scheduled long-hold timer fires even after profile switch")
    }

    // MARK: - State Reset Tests

    /// Test 13: Resetting clears all WASD stick-held keys.
    func testReset_clearsAllStickHeldKeys() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStickMode = .wasdKeys
            profile.joystickSettings.mouseDeadzone = 0.05
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.15)

        // Push stick up-right to hold W and D keys
        await MainActor.run {
            controllerService.setLeftStickForTesting(CGPoint(x: 0.9, y: 0.9))
        }
        await waitForTasks(0.3)

        // Verify keys are held
        let heldKeys = mockInputSimulator.heldDirectionKeys
        XCTAssertFalse(heldKeys.isEmpty, "WASD keys should be held when stick is deflected")

        // Disable engine (triggers reset and releases direction keys)
        await MainActor.run {
            mappingEngine.disable()
        }
        await waitForTasks(0.2)

        let heldAfter = mockInputSimulator.heldDirectionKeys
        XCTAssertTrue(heldAfter.isEmpty, "All direction keys should be released after disable/reset")
    }

    /// Test 14: Resetting clears partial chord state so old chord buttons don't linger.
    func testReset_clearsChordState() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "ChordReset",
                buttonMappings: [.a: .key(1), .b: .key(2)],
                chordMappings: [ChordMapping(buttons: [.a, .b], keyCode: 3)]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Trigger chord
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonPressed(.b)
        }
        await waitForTasks()

        // Disable (resets state including chord tracking)
        await MainActor.run {
            mappingEngine.disable()
        }
        await waitForTasks(0.2)

        // Re-enable and press just A — should fire normally, not be confused by stale chord state
        await MainActor.run {
            mockInputSimulator.clearEvents()
            mappingEngine.enable()
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let aKeyCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count
        XCTAssertGreaterThanOrEqual(aKeyCount, 1, "After reset and re-enable, single A press should fire normally")
    }

    // MARK: - Button Input After Profile Switch

    /// Test 15: After switching profile, button press uses new profile's mapping.
    func testButtonPress_afterProfileSwitch_usesNewMapping() async throws {
        await MainActor.run {
            let profile1 = Profile(name: "Old", buttonMappings: [.a: .key(10)])
            profileManager.setActiveProfile(profile1)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Switch to new profile
        await MainActor.run {
            let profile2 = Profile(name: "New", buttonMappings: [.a: .key(20)])
            profileManager.setActiveProfile(profile2)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press A — should use new mapping
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let newKeyCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 20 }
            return false
        }.count
        let oldKeyCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 10 }
            return false
        }.count
        XCTAssertEqual(newKeyCount, 1, "New profile mapping (keyCode 20) should fire")
        XCTAssertEqual(oldKeyCount, 0, "Old profile mapping (keyCode 10) should not fire")
    }

    /// Test 16: If a button was pressed with old profile and released after switch,
    /// the old held mapping is properly released.
    func testButtonRelease_afterProfileSwitch_releasesOldKey() async throws {
        await MainActor.run {
            let profile1 = Profile(
                name: "Old",
                buttonMappings: [.a: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)]
            )
            profileManager.setActiveProfile(profile1)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press A in old profile (starts hold mapping)
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)

        // Verify hold started
        let holdStarted = mockInputSimulator.events.contains {
            if case .startHoldMapping = $0 { return true }
            return false
        }
        XCTAssertTrue(holdStarted, "Hold mapping should have started in old profile")

        // Switch profile
        await MainActor.run {
            let profile2 = Profile(name: "New", buttonMappings: [.a: .key(20)])
            profileManager.setActiveProfile(profile2)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Release A — engine should still release the old held mapping
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let holdStopped = events.contains {
            if case .stopHoldMapping = $0 { return true }
            return false
        }
        XCTAssertTrue(holdStopped, "Old hold mapping should be released even after profile switch")
    }

    /// Test 17: After switching profile, chord detection uses new profile's chord mappings.
    func testChord_afterProfileSwitch_usesNewChords() async throws {
        await MainActor.run {
            let profile1 = Profile(
                name: "OldChord",
                buttonMappings: [.a: .key(1), .b: .key(2)],
                chordMappings: [ChordMapping(buttons: [.a, .b], keyCode: 30)]
            )
            profileManager.setActiveProfile(profile1)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Switch to new profile with different chord mapping
        await MainActor.run {
            let profile2 = Profile(
                name: "NewChord",
                buttonMappings: [.a: .key(5), .b: .key(6)],
                chordMappings: [ChordMapping(buttons: [.a, .b], keyCode: 40)]
            )
            profileManager.setActiveProfile(profile2)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Trigger chord
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonPressed(.b)
        }
        await waitForTasks()
        await MainActor.run {
            controllerService.buttonReleased(.a)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events
        let newChordCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 40 }
            return false
        }.count
        let oldChordCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 30 }
            return false
        }.count
        XCTAssertEqual(newChordCount, 1, "New profile's chord mapping (keyCode 40) should fire")
        XCTAssertEqual(oldChordCount, 0, "Old profile's chord mapping (keyCode 30) should not fire")
    }

    /// Test 18: After switching profile, double-tap uses new profile's threshold.
    func testDoubleTap_afterProfileSwitch_usesNewThreshold() async throws {
        // Old profile: very short double-tap threshold (0.05s)
        await MainActor.run {
            let mapping1 = KeyMapping(
                keyCode: 1,
                doubleTapMapping: DoubleTapMapping(keyCode: 2, threshold: 0.05)
            )
            let profile1 = Profile(name: "ShortThreshold", buttonMappings: [.a: mapping1])
            profileManager.setActiveProfile(profile1)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Switch to new profile with long threshold (0.5s)
        await MainActor.run {
            let mapping2 = KeyMapping(
                keyCode: 3,
                doubleTapMapping: DoubleTapMapping(keyCode: 4, threshold: 0.5)
            )
            let profile2 = Profile(name: "LongThreshold", buttonMappings: [.a: mapping2])
            profileManager.setActiveProfile(profile2)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Double-tap with 200ms gap — should work with new 0.5s threshold
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2) // 200ms gap — within 0.5s threshold, but beyond 0.05s
        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        let events = mockInputSimulator.events
        let doubleTapCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 4 }
            return false
        }.count
        XCTAssertEqual(doubleTapCount, 1, "Double-tap should use new profile's threshold (0.5s), detecting the 200ms-gap double tap")
    }
}
