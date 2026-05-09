import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Pins `EngineState.reset()` to the contract that **every transient field
/// gets cleared**. The lock-toggle path and the controller-disconnect path
/// both rely on this — a forgotten field means held keys that don't release,
/// timers that don't cancel, or stick smoothing that bleeds across sessions.
///
/// **If you add a new transient field to `EngineState`, you must:**
///   1. Mutate it in `mutateAllTransientFields()` to a non-default value.
///   2. Assert it back to its default in `assertAllTransientFieldsDefault()`.
///   3. Reset it in `EngineState.reset()`.
///
/// Fields that are intentionally NOT reset (config mirrors, profile-derived
/// caches, the lock itself) are deliberately excluded from this test. See
/// `testReset_preservesIntentionallyExcludedFields()` for the explicit list.
final class EngineStateResetTests: XCTestCase {

    func testReset_clearsEveryTransientField() {
        let state = MappingEngine.EngineState()

        mutateAllTransientFields(state)
        assertAllTransientFieldsNonDefault(state, label: "before reset (sanity check on mutator)")

        state.reset()

        assertAllTransientFieldsDefault(state, label: "after reset")
    }

    func testReset_preservesIntentionallyExcludedFields() {
        let state = MappingEngine.EngineState()

        // Set every "preserved" field to a known non-default value.
        state.isEnabled = false
        state.isLocked = true
        state.activeProfile = Profile(name: "Test")
        state.frontmostBundleId = "com.example.test"
        state.joystickSettings = .default
        state.layerActivatorMap = [.a: UUID()]
        state.swipeTypingEnabled = true
        state.swipeTypingSensitivity = 0.9

        state.reset()

        XCTAssertEqual(state.isEnabled, false, "isEnabled is config flag — reset must not touch it")
        XCTAssertEqual(state.isLocked, true, "isLocked is the user-visible mode — reset must not touch it")
        XCTAssertEqual(state.activeProfile?.name, "Test", "activeProfile is a config mirror")
        XCTAssertEqual(state.frontmostBundleId, "com.example.test", "frontmostBundleId is set externally")
        XCTAssertNotNil(state.joystickSettings, "joystickSettings is a config mirror")
        XCTAssertFalse(state.layerActivatorMap.isEmpty, "layerActivatorMap is rebuilt on profile changes, not reset")
        XCTAssertTrue(state.swipeTypingEnabled, "swipeTypingEnabled is config-derived")
        XCTAssertEqual(state.swipeTypingSensitivity, 0.9, accuracy: 1e-10, "swipeTypingSensitivity is config-derived")
    }

    // MARK: - Mutators

    private func mutateAllTransientFields(_ state: MappingEngine.EngineState) {
        let dummyButton = ControllerButton.a
        let dummyMapping = KeyMapping(keyCode: 0)
        let dummyWorkItem = DispatchWorkItem(block: {})
        // Timer must be resumed before release; libdispatch traps on releasing
        // a suspended source. Schedule it far in the future so it won't fire.
        let dummyTimer = DispatchSource.makeTimerSource()
        dummyTimer.setEventHandler {}
        dummyTimer.schedule(deadline: .distantFuture)
        dummyTimer.resume()

        state.chordParticipantButtons = [dummyButton]
        state.sequenceParticipantButtons = [dummyButton]
        state.chordLookup = [[dummyButton]: ChordMapping(buttons: [dummyButton])]

        state.heldButtons = [dummyButton: dummyMapping]
        state.activeChordButtons = [dummyButton]
        state.lastTapTime = [dummyButton: 1.0]
        state.pendingSingleTap = [dummyButton: dummyWorkItem]
        state.pendingReleaseActions = [dummyButton: dummyWorkItem]
        state.longHoldTimers = [dummyButton: dummyWorkItem]
        state.longHoldTriggered = [dummyButton]
        state.repeatTimers = [dummyButton: dummyTimer]
        state.holdRepeatTimers = [dummyButton: dummyTimer]

        state.sequenceDetector.configure(sequences: [
            SequenceMapping(steps: [.a, .b])
        ])
        // Drive the detector so it has non-empty activeSequences.
        _ = state.sequenceDetector.process(.a, at: 0)

        state.onScreenKeyboardButton = dummyButton
        state.onScreenKeyboardHoldMode = true
        state.laserPointerButton = dummyButton
        state.laserPointerHoldMode = true
        state.directoryNavigatorButton = dummyButton
        state.directoryNavigatorHoldMode = true
        state.commandWheelButton = dummyButton
        state.commandWheelHoldMode = true
        state.commandWheelActive = true
        state.wheelAlternateModifiers = .command
        state.dpadNavigationTimer = dummyTimer
        state.dpadNavigationButton = dummyButton

        state.activeLayerIds = [UUID()]
        state.buttonsActingAsLayerActivators = [dummyButton]
        state.pressConsumedByAction = [dummyButton]

        state.smoothedLeftStick = CGPoint(x: 0.5, y: 0.5)
        state.smoothedRightStick = CGPoint(x: 0.5, y: 0.5)
        state.leftStickHeldKeys = [13]
        state.rightStickHeldKeys = [13]
        state.lastJoystickSampleTime = 1.0
        state.smoothedTouchpadDelta = CGPoint(x: 1, y: 1)
        state.lastTouchpadSampleTime = 1.0
        state.smoothedTouchpadCenterDelta = CGPoint(x: 1, y: 1)
        state.smoothedTouchpadDistanceDelta = 1.0
        state.lastTouchpadGestureSampleTime = 1.0
        state.isTouchpadGestureActive = true
        state.touchpadScrollResidualX = 1.0
        state.touchpadScrollResidualY = 1.0
        state.touchpadMomentumVelocity = CGPoint(x: 1, y: 1)
        state.touchpadMomentumLastUpdate = 1.0
        state.touchpadMomentumLastGestureTime = 1.0
        state.touchpadMomentumWasActive = true
        state.touchpadMomentumCandidateVelocity = CGPoint(x: 1, y: 1)
        state.touchpadMomentumCandidateTime = 1.0
        state.touchpadMomentumHighVelocityStartTime = 1.0
        state.touchpadMomentumHighVelocitySampleCount = 5
        state.touchpadMomentumPeakVelocity = CGPoint(x: 1, y: 1)
        state.touchpadMomentumPeakMagnitude = 1.0
        state.smoothedTouchpadPanVelocity = CGPoint(x: 1, y: 1)
        state.touchpadPanActive = true
        state.touchpadPinchAccumulator = 1.0
        state.touchpadMagnifyGestureActive = true
        state.touchpadMagnifyDirection = 1.0
        state.touchpadMagnifyDirectionLockUntil = 1.0

        state.rightStickWasOutsideDeadzone = true
        state.rightStickPeakYAbs = 1.0
        state.rightStickLastDirection = 1
        state.lastRightStickTapTime = 1.0
        state.lastRightStickTapDirection = 1
        state.scrollBoostDirection = 1

        state.swipeTypingActive = true
        state.swipeTypingCursorX = 0.1
        state.swipeTypingCursorY = 0.1
        state.wasTouchpadTouching = true
        state.swipeClickReleaseFrames = 3

        state.directoryNavLastMoveTime = 1.0
        state.directoryNavStickWasInDeadzone = false

        state.wasFocusActive = true
        state.currentMultiplier = 5.0
        state.focusExitTime = 1.0
        state.lastGyroTime = 1.0
    }

    // MARK: - Assertions

    private func assertAllTransientFieldsNonDefault(_ state: MappingEngine.EngineState, label: String) {
        // Spot-check a few mutated fields to catch a bug in the mutator itself.
        XCTAssertFalse(state.heldButtons.isEmpty, "[\(label)] mutator should have populated heldButtons")
        XCTAssertNotEqual(state.smoothedLeftStick, .zero, "[\(label)] mutator should have populated smoothedLeftStick")
        XCTAssertTrue(state.commandWheelActive, "[\(label)] mutator should have set commandWheelActive")
    }

    private func assertAllTransientFieldsDefault(_ state: MappingEngine.EngineState, label: String) {
        XCTAssertTrue(state.chordParticipantButtons.isEmpty, "[\(label)] chordParticipantButtons")
        XCTAssertTrue(state.sequenceParticipantButtons.isEmpty, "[\(label)] sequenceParticipantButtons")
        XCTAssertTrue(state.chordLookup.isEmpty, "[\(label)] chordLookup")

        XCTAssertTrue(state.heldButtons.isEmpty, "[\(label)] heldButtons — held keys would never release")
        XCTAssertTrue(state.activeChordButtons.isEmpty, "[\(label)] activeChordButtons")
        XCTAssertTrue(state.lastTapTime.isEmpty, "[\(label)] lastTapTime — stale taps could trigger spurious double-taps")
        XCTAssertTrue(state.pendingSingleTap.isEmpty, "[\(label)] pendingSingleTap — pending taps would fire post-reset")
        XCTAssertTrue(state.pendingReleaseActions.isEmpty, "[\(label)] pendingReleaseActions")
        XCTAssertTrue(state.longHoldTimers.isEmpty, "[\(label)] longHoldTimers — long-hold could fire after reset")
        XCTAssertTrue(state.longHoldTriggered.isEmpty, "[\(label)] longHoldTriggered")
        XCTAssertTrue(state.repeatTimers.isEmpty, "[\(label)] repeatTimers — key repeat would continue post-reset")
        XCTAssertTrue(state.holdRepeatTimers.isEmpty, "[\(label)] holdRepeatTimers")

        XCTAssertTrue(state.sequenceDetector.activeSequences.isEmpty, "[\(label)] sequenceDetector — partial sequences could complete spuriously")

        XCTAssertNil(state.onScreenKeyboardButton, "[\(label)] onScreenKeyboardButton")
        XCTAssertFalse(state.onScreenKeyboardHoldMode, "[\(label)] onScreenKeyboardHoldMode")
        XCTAssertNil(state.laserPointerButton, "[\(label)] laserPointerButton")
        XCTAssertFalse(state.laserPointerHoldMode, "[\(label)] laserPointerHoldMode")
        XCTAssertNil(state.directoryNavigatorButton, "[\(label)] directoryNavigatorButton")
        XCTAssertFalse(state.directoryNavigatorHoldMode, "[\(label)] directoryNavigatorHoldMode")
        XCTAssertNil(state.commandWheelButton, "[\(label)] commandWheelButton")
        XCTAssertFalse(state.commandWheelHoldMode, "[\(label)] commandWheelHoldMode")
        XCTAssertFalse(state.commandWheelActive, "[\(label)] commandWheelActive")
        XCTAssertEqual(state.wheelAlternateModifiers, ModifierFlags(), "[\(label)] wheelAlternateModifiers")

        XCTAssertNil(state.dpadNavigationTimer, "[\(label)] dpadNavigationTimer")
        XCTAssertNil(state.dpadNavigationButton, "[\(label)] dpadNavigationButton")

        XCTAssertTrue(state.activeLayerIds.isEmpty, "[\(label)] activeLayerIds — locked-in layer would persist")
        XCTAssertTrue(state.buttonsActingAsLayerActivators.isEmpty, "[\(label)] buttonsActingAsLayerActivators")
        XCTAssertTrue(state.pressConsumedByAction.isEmpty, "[\(label)] pressConsumedByAction")

        XCTAssertEqual(state.smoothedLeftStick, .zero, "[\(label)] smoothedLeftStick — residual smoothing would bleed across sessions")
        XCTAssertEqual(state.smoothedRightStick, .zero, "[\(label)] smoothedRightStick")
        XCTAssertTrue(state.leftStickHeldKeys.isEmpty, "[\(label)] leftStickHeldKeys — WASD keys would stay held")
        XCTAssertTrue(state.rightStickHeldKeys.isEmpty, "[\(label)] rightStickHeldKeys")
        XCTAssertEqual(state.lastJoystickSampleTime, 0, "[\(label)] lastJoystickSampleTime")

        XCTAssertEqual(state.smoothedTouchpadDelta, .zero, "[\(label)] smoothedTouchpadDelta")
        XCTAssertEqual(state.lastTouchpadSampleTime, 0, "[\(label)] lastTouchpadSampleTime")
        XCTAssertEqual(state.smoothedTouchpadCenterDelta, .zero, "[\(label)] smoothedTouchpadCenterDelta")
        XCTAssertEqual(state.smoothedTouchpadDistanceDelta, 0, "[\(label)] smoothedTouchpadDistanceDelta")
        XCTAssertEqual(state.lastTouchpadGestureSampleTime, 0, "[\(label)] lastTouchpadGestureSampleTime")
        XCTAssertFalse(state.isTouchpadGestureActive, "[\(label)] isTouchpadGestureActive")
        XCTAssertEqual(state.touchpadScrollResidualX, 0, "[\(label)] touchpadScrollResidualX")
        XCTAssertEqual(state.touchpadScrollResidualY, 0, "[\(label)] touchpadScrollResidualY")
        XCTAssertEqual(state.touchpadMomentumVelocity, .zero, "[\(label)] touchpadMomentumVelocity — momentum would persist")
        XCTAssertEqual(state.touchpadMomentumLastUpdate, 0, "[\(label)] touchpadMomentumLastUpdate")
        XCTAssertEqual(state.touchpadMomentumLastGestureTime, 0, "[\(label)] touchpadMomentumLastGestureTime")
        XCTAssertFalse(state.touchpadMomentumWasActive, "[\(label)] touchpadMomentumWasActive")
        XCTAssertEqual(state.touchpadMomentumCandidateVelocity, .zero, "[\(label)] touchpadMomentumCandidateVelocity")
        XCTAssertEqual(state.touchpadMomentumCandidateTime, 0, "[\(label)] touchpadMomentumCandidateTime")
        XCTAssertEqual(state.touchpadMomentumHighVelocityStartTime, 0, "[\(label)] touchpadMomentumHighVelocityStartTime")
        XCTAssertEqual(state.touchpadMomentumHighVelocitySampleCount, 0, "[\(label)] touchpadMomentumHighVelocitySampleCount")
        XCTAssertEqual(state.touchpadMomentumPeakVelocity, .zero, "[\(label)] touchpadMomentumPeakVelocity")
        XCTAssertEqual(state.touchpadMomentumPeakMagnitude, 0, "[\(label)] touchpadMomentumPeakMagnitude")
        XCTAssertEqual(state.smoothedTouchpadPanVelocity, .zero, "[\(label)] smoothedTouchpadPanVelocity")
        XCTAssertFalse(state.touchpadPanActive, "[\(label)] touchpadPanActive")
        XCTAssertEqual(state.touchpadPinchAccumulator, 0, "[\(label)] touchpadPinchAccumulator")
        XCTAssertFalse(state.touchpadMagnifyGestureActive, "[\(label)] touchpadMagnifyGestureActive")
        XCTAssertEqual(state.touchpadMagnifyDirection, 0, "[\(label)] touchpadMagnifyDirection")
        XCTAssertEqual(state.touchpadMagnifyDirectionLockUntil, 0, "[\(label)] touchpadMagnifyDirectionLockUntil")

        XCTAssertFalse(state.rightStickWasOutsideDeadzone, "[\(label)] rightStickWasOutsideDeadzone")
        XCTAssertEqual(state.rightStickPeakYAbs, 0, "[\(label)] rightStickPeakYAbs")
        XCTAssertEqual(state.rightStickLastDirection, 0, "[\(label)] rightStickLastDirection")
        XCTAssertEqual(state.lastRightStickTapTime, 0, "[\(label)] lastRightStickTapTime")
        XCTAssertEqual(state.lastRightStickTapDirection, 0, "[\(label)] lastRightStickTapDirection")
        XCTAssertEqual(state.scrollBoostDirection, 0, "[\(label)] scrollBoostDirection")

        XCTAssertFalse(state.swipeTypingActive, "[\(label)] swipeTypingActive")
        XCTAssertEqual(state.swipeTypingCursorX, 0.5, accuracy: 1e-10, "[\(label)] swipeTypingCursorX")
        XCTAssertEqual(state.swipeTypingCursorY, 0.5, accuracy: 1e-10, "[\(label)] swipeTypingCursorY")
        XCTAssertFalse(state.wasTouchpadTouching, "[\(label)] wasTouchpadTouching")
        XCTAssertEqual(state.swipeClickReleaseFrames, 0, "[\(label)] swipeClickReleaseFrames")

        XCTAssertEqual(state.directoryNavLastMoveTime, 0, "[\(label)] directoryNavLastMoveTime")
        XCTAssertTrue(state.directoryNavStickWasInDeadzone, "[\(label)] directoryNavStickWasInDeadzone")

        XCTAssertFalse(state.wasFocusActive, "[\(label)] wasFocusActive")
        XCTAssertEqual(state.currentMultiplier, 0, "[\(label)] currentMultiplier")
        XCTAssertEqual(state.focusExitTime, 0, "[\(label)] focusExitTime")
        XCTAssertEqual(state.lastGyroTime, 0, "[\(label)] lastGyroTime")
    }
}
