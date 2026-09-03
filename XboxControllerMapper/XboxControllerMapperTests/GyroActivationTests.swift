import XCTest
import CoreGraphics
@testable import ControllerKeys

// MARK: - Resolver Truth Table

/// Pure-function coverage of GyroActivationResolver: pause beats hold, toggle is
/// additive in legacy mode, alwaysOn starts latched on, gyroButton starts off.
final class GyroActivationResolverTests: XCTestCase {

    private func active(
        _ mode: GyroActivationMode,
        focus: Bool = false,
        toggled: Bool = false,
        hold: Bool = false,
        pause: Bool = false
    ) -> Bool {
        GyroActivationResolver.isActive(
            mode: mode,
            isFocusActive: focus,
            toggledOn: toggled,
            holdButtonsDown: hold,
            pauseButtonsDown: pause
        )
    }

    func testPauseBeatsEverything() {
        for mode in GyroActivationMode.allCases {
            XCTAssertFalse(
                active(mode, focus: true, toggled: true, hold: true, pause: true),
                "Pause must suppress gyro in mode \(mode)"
            )
        }
    }

    func testFocusModifierLegacyBehavior() {
        XCTAssertTrue(active(.focusModifier, focus: true))
        XCTAssertFalse(active(.focusModifier, focus: false))
    }

    func testFocusModifierToggleIsAdditive() {
        XCTAssertTrue(active(.focusModifier, focus: false, toggled: true))
        XCTAssertTrue(active(.focusModifier, focus: true, toggled: true))
    }

    func testAlwaysOnFollowsLatch() {
        XCTAssertTrue(active(.alwaysOn, toggled: true))
        XCTAssertFalse(active(.alwaysOn, toggled: false), "Toggle can park always-on off")
        XCTAssertTrue(active(.alwaysOn, toggled: false, hold: true), "Hold overrides a parked-off latch")
    }

    func testGyroButtonMode() {
        XCTAssertFalse(active(.gyroButton))
        XCTAssertTrue(active(.gyroButton, toggled: true))
        XCTAssertTrue(active(.gyroButton, hold: true))
        XCTAssertFalse(active(.gyroButton, focus: true), "Focus modifier must not activate gyro in gyroButton mode")
    }

    func testHoldReleaseDeactivatesWhenBaseOff() {
        XCTAssertTrue(active(.gyroButton, hold: true))
        XCTAssertFalse(active(.gyroButton, hold: false))
    }

    func testInitialToggledOn() {
        XCTAssertFalse(GyroActivationMode.focusModifier.initialToggledOn)
        XCTAssertTrue(GyroActivationMode.alwaysOn.initialToggledOn)
        XCTAssertFalse(GyroActivationMode.gyroButton.initialToggledOn)
    }

    func testGyroButtonActionKeycodeMapping() {
        XCTAssertEqual(GyroButtonAction(keyCode: KeyCodeMapping.gyroToggle), .toggle)
        XCTAssertEqual(GyroButtonAction(keyCode: KeyCodeMapping.gyroHold), .hold)
        XCTAssertEqual(GyroButtonAction(keyCode: KeyCodeMapping.gyroPause), .pause)
        XCTAssertNil(GyroButtonAction(keyCode: 1))
        XCTAssertNil(GyroButtonAction(keyCode: KeyCodeMapping.showLaserPointer))
    }

    func testGyroKeycodesAreSpecialMarkers() {
        for code in [KeyCodeMapping.gyroToggle, KeyCodeMapping.gyroHold, KeyCodeMapping.gyroPause] {
            XCTAssertTrue(KeyCodeMapping.isGyroAction(code))
            XCTAssertTrue(KeyCodeMapping.isSpecialAction(code))
            XCTAssertTrue(KeyCodeMapping.isSpecialMarker(code), "Gyro markers must never post as raw key events")
        }
    }
}

// MARK: - Settings Decode Migration

final class GyroActivationModeDecodeTests: XCTestCase {

    private func decodeSettings(_ json: String) throws -> JoystickSettings {
        try JSONDecoder().decode(JoystickSettings.self, from: Data(json.utf8))
    }

    func testMissingModeDecodesToLegacy() throws {
        let settings = try decodeSettings("{}")
        XCTAssertEqual(settings.gyroActivationMode, .focusModifier)
    }

    func testGarbageModeDecodesToLegacy() throws {
        let settings = try decodeSettings(#"{"gyroActivationMode": "warpSpeed"}"#)
        XCTAssertEqual(settings.gyroActivationMode, .focusModifier)
    }

    func testModeRoundTrip() throws {
        var settings = JoystickSettings.default
        settings.gyroActivationMode = .alwaysOn
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(JoystickSettings.self, from: data)
        XCTAssertEqual(decoded.gyroActivationMode, .alwaysOn)
    }
}

// MARK: - Engine State Reset

final class GyroEngineStateResetTests: XCTestCase {

    func testResetClearsGyroTransientsAndReDerivesLatch() {
        let state = MappingEngine.EngineState()
        state.lock.lock()
        state.gyroToggledOn = true
        state.gyroHoldButtons = [.a, .micMute]
        state.gyroPauseButtons = [.b]
        state.wasGyroActive = true
        state.reset()
        state.lock.unlock()

        // No settings bound -> default settings -> focusModifier -> latch false.
        XCTAssertFalse(state.gyroToggledOn)
        XCTAssertTrue(state.gyroHoldButtons.isEmpty)
        XCTAssertTrue(state.gyroPauseButtons.isEmpty)
        XCTAssertFalse(state.wasGyroActive)
    }

    func testResetReDerivesLatchFromAlwaysOnMode() {
        let state = MappingEngine.EngineState()
        var settings = JoystickSettings.default
        settings.gyroActivationMode = .alwaysOn
        state.lock.lock()
        state.joystickSettings = settings
        state.gyroToggledOn = false // parked off by the user
        state.reset()
        state.lock.unlock()

        XCTAssertTrue(state.gyroToggledOn, "Always-on re-arms across a full reset")
    }

    func testPreservingGyroStateSurvivesIntraSessionBoundary() {
        let state = MappingEngine.EngineState()
        state.lock.lock()
        state.gyroToggledOn = true
        state.gyroHoldButtons = [.micMute]
        state.gyroPauseButtons = [.b]
        state.wasGyroActive = true
        state.resetTransientInputState(
            preservingManualLayers: true,
            preservingUIOverlays: true,
            preservingGyroState: true
        )
        state.lock.unlock()

        XCTAssertTrue(state.gyroToggledOn, "Latch survives app-layer/layer-toggle boundaries")
        XCTAssertTrue(state.gyroHoldButtons.contains(.micMute), "Held gyro button survives the boundary")
        XCTAssertTrue(state.gyroPauseButtons.contains(.b))
        XCTAssertTrue(state.wasGyroActive, "No manufactured activation edge")
    }

    func testGyroActiveLockedGatesOnEnabledAndLocked() {
        let state = MappingEngine.EngineState()
        var settings = JoystickSettings.default
        settings.gyroAimingEnabled = true
        settings.gyroActivationMode = .alwaysOn
        state.lock.lock()
        defer { state.lock.unlock() }
        state.joystickSettings = settings
        state.gyroToggledOn = true

        state.isEnabled = true
        state.isLocked = false
        XCTAssertTrue(state.gyroActiveLocked(isFocusActive: false))

        state.isLocked = true
        XCTAssertFalse(state.gyroActiveLocked(isFocusActive: false), "Controller Lock must gate gyroIsActive()")

        state.isLocked = false
        state.isEnabled = false
        XCTAssertFalse(state.gyroActiveLocked(isFocusActive: false), "Disabled mappings must gate gyroIsActive()")
    }
}

// MARK: - Executor Honest Dispatch

final class SpecialMarkerDispatchTests: XCTestCase {

    func testKeyPressCommandReportsNonDispatchForSpecialMarkers() {
        let mock = MockInputSimulator()
        let mapping = KeyMapping(keyCode: KeyCodeMapping.showLaserPointer)
        let command = KeyPressActionCommand(
            keyCode: KeyCodeMapping.showLaserPointer,
            modifiers: ModifierFlags(),
            inputSimulator: mock,
            action: mapping
        )

        let outcome = command.executeWithOutcome()

        XCTAssertFalse(outcome.didDispatch, "Swallowed special markers must not report success")
        XCTAssertTrue(mock.events.isEmpty, "No input events for a special marker")
    }

    func testKeyPressCommandStillDispatchesRealKeys() {
        let mock = MockInputSimulator()
        let mapping = KeyMapping(keyCode: 6) // Z
        let command = KeyPressActionCommand(
            keyCode: 6,
            modifiers: ModifierFlags(),
            inputSimulator: mock,
            action: mapping
        )

        let outcome = command.executeWithOutcome()

        XCTAssertTrue(outcome.didDispatch)
        XCTAssertTrue(mock.events.contains { event in
            if case .pressKey(let code, _) = event { return code == 6 }
            return false
        })
    }
}

// MARK: - Engine Integration (press/release intercepts)

final class GyroActionInterceptTests: MappingEngineTestCase {

    private func noGyroKeyEventsEmitted() -> Bool {
        !mockInputSimulator.events.contains { event in
            if case .pressKey(let code, _) = event { return KeyCodeMapping.isGyroAction(code) }
            return false
        }
    }

    func testGyroHoldTracksPressAndRelease() async throws {
        await MainActor.run {
            var settings = JoystickSettings.default
            settings.gyroAimingEnabled = true
            settings.gyroActivationMode = .gyroButton
            let mapping = KeyMapping(keyCode: KeyCodeMapping.gyroHold)
            profileManager.setActiveProfile(
                Profile(name: "GyroHold", buttonMappings: [.micMute: mapping], joystickSettings: settings)
            )
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run { controllerService.buttonPressed(.micMute) }
        await waitForTasks(0.2)
        let heldAfterPress = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroHoldButtons.contains(.micMute) }
        }
        XCTAssertTrue(heldAfterPress, "Press should register the hold button")
        let consumed = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.pressConsumedByAction.contains(.micMute) }
        }
        XCTAssertTrue(consumed, "Gyro press must mark pressConsumedByAction so the release is suppressed from press-time state")

        await MainActor.run { controllerService.buttonReleased(.micMute) }
        await waitForTasks(0.2)
        let heldAfterRelease = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroHoldButtons.contains(.micMute) }
        }
        XCTAssertFalse(heldAfterRelease, "Release should clear the hold button")
        let cleanEvents = noGyroKeyEventsEmitted()
        XCTAssertTrue(cleanEvents, "Gyro actions must not emit key events")
    }

    func testGyroPauseTracksPressAndRelease() async throws {
        await MainActor.run {
            var settings = JoystickSettings.default
            settings.gyroAimingEnabled = true
            settings.gyroActivationMode = .alwaysOn
            let mapping = KeyMapping(keyCode: KeyCodeMapping.gyroPause)
            profileManager.setActiveProfile(
                Profile(name: "GyroPause", buttonMappings: [.micMute: mapping], joystickSettings: settings)
            )
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run { controllerService.buttonPressed(.micMute) }
        await waitForTasks(0.2)
        let pausedAfterPress = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroPauseButtons.contains(.micMute) }
        }
        XCTAssertTrue(pausedAfterPress)

        await MainActor.run { controllerService.buttonReleased(.micMute) }
        await waitForTasks(0.2)
        let pausedAfterRelease = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroPauseButtons.contains(.micMute) }
        }
        XCTAssertFalse(pausedAfterRelease)
        let cleanEvents = noGyroKeyEventsEmitted()
        XCTAssertTrue(cleanEvents)
    }

    func testGyroToggleFlipsLatch() async throws {
        await MainActor.run {
            var settings = JoystickSettings.default
            settings.gyroAimingEnabled = true
            settings.gyroActivationMode = .gyroButton
            let mapping = KeyMapping(keyCode: KeyCodeMapping.gyroToggle)
            profileManager.setActiveProfile(
                Profile(name: "GyroToggle", buttonMappings: [.y: mapping], joystickSettings: settings)
            )
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // gyroButton mode starts with the latch off.
        let initialLatch = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroToggledOn }
        }
        XCTAssertFalse(initialLatch)

        await MainActor.run {
            controllerService.buttonPressed(.y)
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.2)
        let latchAfterFirstTap = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroToggledOn }
        }
        XCTAssertTrue(latchAfterFirstTap)

        await MainActor.run {
            controllerService.buttonPressed(.y)
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.2)
        let latchAfterSecondTap = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroToggledOn }
        }
        XCTAssertFalse(latchAfterSecondTap)
        let cleanEvents = noGyroKeyEventsEmitted()
        XCTAssertTrue(cleanEvents)
    }

    func testAlwaysOnProfileStartsLatchedOn() async throws {
        await MainActor.run {
            var settings = JoystickSettings.default
            settings.gyroAimingEnabled = true
            settings.gyroActivationMode = .alwaysOn
            profileManager.setActiveProfile(
                Profile(name: "AlwaysOn", joystickSettings: settings)
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let latch = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroToggledOn }
        }
        XCTAssertTrue(latch, "Switching to an always-on profile must arm the latch")
    }

    func testSettingsRepublishPreservesLatchAndModeChangeRederives() async throws {
        await MainActor.run {
            var settings = JoystickSettings.default
            settings.gyroAimingEnabled = true
            settings.gyroActivationMode = .gyroButton
            let mapping = KeyMapping(keyCode: KeyCodeMapping.gyroToggle)
            profileManager.setActiveProfile(
                Profile(name: "LatchLifecycle", buttonMappings: [.y: mapping], joystickSettings: settings)
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Latch gyro ON via the toggle button.
        await MainActor.run {
            controllerService.buttonPressed(.y)
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.2)
        var latch = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroToggledOn }
        }
        XCTAssertTrue(latch)

        // A same-profile settings edit (slider tick) must NOT reset the latch.
        await MainActor.run {
            guard var settings = profileManager.activeProfile?.joystickSettings else {
                return XCTFail("missing settings")
            }
            settings.gyroAimingSensitivity = 0.7
            profileManager.updateJoystickSettings(settings)
        }
        await waitForTasks(0.2)
        latch = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroToggledOn }
        }
        XCTAssertTrue(latch, "Settings republish for the same profile must preserve the toggle latch")

        // Changing the activation mode re-derives the latch from the new mode.
        await MainActor.run {
            guard var settings = profileManager.activeProfile?.joystickSettings else {
                return XCTFail("missing settings")
            }
            settings.gyroActivationMode = .focusModifier
            profileManager.updateJoystickSettings(settings)
        }
        await waitForTasks(0.2)
        latch = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.gyroToggledOn }
        }
        XCTAssertFalse(latch, "Mode change re-derives the latch from the new mode's initial state")
    }

    func testSpecialActionReleaseDoesNotReExecute() async throws {
        // Controller Lock in toggle mode (isHoldModifier=false): press locks,
        // second press unlocks; neither release may re-execute the mapping and
        // hand the marker keycode to the executor (the pre-existing laser bug
        // generalized by the special-action release guard).
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock, isHoldModifier: false)
            profileManager.setActiveProfile(
                Profile(name: "LockToggle", buttonMappings: [.y: mapping])
            )
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.y)
            controllerService.buttonReleased(.y)
            controllerService.buttonPressed(.y)
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.3)

        let markerKeyEvents = mockInputSimulator.events.contains { event in
            if case .pressKey(let code, _) = event { return KeyCodeMapping.isSpecialAction(code) }
            return false
        }
        XCTAssertFalse(markerKeyEvents, "Special-action markers must never reach pressKey via release")
        let locked = await MainActor.run {
            mappingEngine.state.lock.withLock { mappingEngine.state.isLocked }
        }
        XCTAssertFalse(locked, "Two presses = lock then unlock")
    }
}
