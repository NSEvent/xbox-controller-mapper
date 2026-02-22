import XCTest
@testable import ControllerKeys

final class MotionGestureDetectorTests: XCTestCase {
    var detector: MotionGestureDetector!

    override func setUp() {
        detector = MotionGestureDetector()
    }

    override func tearDown() {
        detector = nil
    }

    /// Simulate a quick tilt-back gesture: velocity rises above threshold, peaks, then drops.
    func testTiltBackDetected() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureActivationThreshold
        let minPeakVelocity = Config.gestureMinPeakVelocity

        // Start with velocity above activation threshold (positive pitch = tilt back)
        var results = detector.processAll((pitchRate: activationThreshold + 1.0, rollRate: 0), at: now)
        XCTAssertTrue(results.isEmpty, "Should not fire during tracking phase")

        // Peak velocity
        results = detector.processAll((pitchRate: minPeakVelocity + 2.0, rollRate: 0), at: now + 0.01)
        XCTAssertTrue(results.isEmpty, "Should not fire while velocity is still high")

        // Velocity drops below completion ratio (peak * 0.3)
        let completionVelocity = (minPeakVelocity + 2.0) * Config.gestureCompletionRatio * 0.5
        results = detector.processAll((pitchRate: completionVelocity, rollRate: 0), at: now + 0.05)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first, .tiltBack, "Positive pitch should be tilt back")
    }

    /// Simulate a tilt-forward gesture: negative pitch velocity.
    func testTiltForwardDetected() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureActivationThreshold
        let minPeakVelocity = Config.gestureMinPeakVelocity

        // Negative pitch = tilt forward
        _ = detector.processAll((pitchRate: -(activationThreshold + 1.0), rollRate: 0), at: now)
        _ = detector.processAll((pitchRate: -(minPeakVelocity + 2.0), rollRate: 0), at: now + 0.01)

        let completionVelocity = (minPeakVelocity + 2.0) * Config.gestureCompletionRatio * 0.5
        let results = detector.processAll((pitchRate: -completionVelocity, rollRate: 0), at: now + 0.05)
        XCTAssertEqual(results.first, .tiltForward, "Negative pitch should be tilt forward")
    }

    /// Simulate a steer-left gesture: positive roll velocity.
    func testSteerLeftDetected() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureRollActivationThreshold
        let minPeakVelocity = Config.gestureRollMinPeakVelocity

        _ = detector.processAll((pitchRate: 0, rollRate: activationThreshold + 1.0), at: now)
        _ = detector.processAll((pitchRate: 0, rollRate: minPeakVelocity + 2.0), at: now + 0.01)

        let completionVelocity = (minPeakVelocity + 2.0) * Config.gestureCompletionRatio * 0.5
        let results = detector.processAll((pitchRate: 0, rollRate: completionVelocity), at: now + 0.05)
        XCTAssertEqual(results.first, .steerLeft, "Positive roll should be steer left")
    }

    /// Simulate a steer-right gesture: negative roll velocity.
    func testSteerRightDetected() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureRollActivationThreshold
        let minPeakVelocity = Config.gestureRollMinPeakVelocity

        _ = detector.processAll((pitchRate: 0, rollRate: -(activationThreshold + 1.0)), at: now)
        _ = detector.processAll((pitchRate: 0, rollRate: -(minPeakVelocity + 2.0)), at: now + 0.01)

        let completionVelocity = (minPeakVelocity + 2.0) * Config.gestureCompletionRatio * 0.5
        let results = detector.processAll((pitchRate: 0, rollRate: -completionVelocity), at: now + 0.05)
        XCTAssertEqual(results.first, .steerRight, "Negative roll should be steer right")
    }

    /// Slow, deliberate motion should not trigger a gesture.
    func testSlowMotionDoesNotTrigger() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureActivationThreshold

        // Start tracking
        _ = detector.processAll((pitchRate: activationThreshold + 0.5, rollRate: 0), at: now)

        // Exceed max duration without peaking enough
        let maxDuration = Config.gestureMaxDuration
        let results = detector.processAll((pitchRate: activationThreshold + 0.5, rollRate: 0), at: now + maxDuration + 0.01)
        XCTAssertTrue(results.isEmpty, "Slow motion exceeding max duration should not trigger gesture")
    }

    /// Reset should clear all state.
    func testResetClearsState() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureActivationThreshold

        // Start tracking on pitch
        _ = detector.processAll((pitchRate: activationThreshold + 1.0, rollRate: 0), at: now)
        XCTAssertNotEqual(detector.pitchState.phase, .idle, "Pitch should be tracking")

        detector.reset()
        XCTAssertEqual(detector.pitchState.phase, .idle, "Pitch should be idle after reset")
        XCTAssertEqual(detector.rollState.phase, .idle, "Roll should be idle after reset")
    }

    /// process() returns nil when no gesture is detected (zero velocity input).
    func testProcessReturnsNilForZeroVelocity() {
        let now = CFAbsoluteTimeGetCurrent()
        let result = detector.process((pitchRate: 0, rollRate: 0), at: now)
        XCTAssertNil(result, "No gesture for zero velocity")
    }

    /// When both pitch and roll complete simultaneously, process() returns only
    /// the first result (pitch) while processAll() returns both.
    func testProcessReturnsSingleResultWhenBothAxesTrigger() {
        let now = CFAbsoluteTimeGetCurrent()
        let pitchActivation = Config.gestureActivationThreshold
        let pitchPeak = Config.gestureMinPeakVelocity
        let rollActivation = Config.gestureRollActivationThreshold
        let rollPeak = Config.gestureRollMinPeakVelocity

        // Start tracking on both axes simultaneously
        _ = detector.processAll(
            (pitchRate: pitchActivation + 1.0, rollRate: rollActivation + 1.0),
            at: now
        )

        // Peak on both axes
        _ = detector.processAll(
            (pitchRate: pitchPeak + 2.0, rollRate: rollPeak + 2.0),
            at: now + 0.01
        )

        // Drop below completion on both axes
        let pitchCompletion = (pitchPeak + 2.0) * Config.gestureCompletionRatio * 0.5
        let rollCompletion = (rollPeak + 2.0) * Config.gestureCompletionRatio * 0.5

        let allResults = detector.processAll(
            (pitchRate: pitchCompletion, rollRate: rollCompletion),
            at: now + 0.05
        )
        XCTAssertEqual(allResults.count, 2, "processAll() should return both gestures")
        XCTAssertEqual(allResults[0], .tiltBack, "First result should be pitch gesture (tiltBack)")
        XCTAssertEqual(allResults[1], .steerLeft, "Second result should be roll gesture (steerLeft)")

        // Now test process() in a fresh detector with the same scenario
        let detector2 = MotionGestureDetector()
        _ = detector2.processAll(
            (pitchRate: pitchActivation + 1.0, rollRate: rollActivation + 1.0),
            at: now + 10
        )
        _ = detector2.processAll(
            (pitchRate: pitchPeak + 2.0, rollRate: rollPeak + 2.0),
            at: now + 10.01
        )
        let singleResult = detector2.process(
            (pitchRate: pitchCompletion, rollRate: rollCompletion),
            at: now + 10.05
        )
        XCTAssertEqual(singleResult, .tiltBack, "process() should return only the first (pitch) result")
    }

    // MARK: - Cooldown Tests

    /// A gesture in the same direction during the cooldown period should be rejected.
    func testSameDirectionCooldownRejectsGesture() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureActivationThreshold
        let minPeakVelocity = Config.gestureMinPeakVelocity
        let cooldown = Config.gestureCooldown

        // Fire a tiltBack gesture
        _ = detector.processAll((pitchRate: activationThreshold + 1.0, rollRate: 0), at: now)
        _ = detector.processAll((pitchRate: minPeakVelocity + 2.0, rollRate: 0), at: now + 0.01)
        let completionVelocity = (minPeakVelocity + 2.0) * Config.gestureCompletionRatio * 0.5
        let firstResult = detector.processAll((pitchRate: completionVelocity, rollRate: 0), at: now + 0.05)
        XCTAssertEqual(firstResult.count, 1, "First gesture should fire")
        XCTAssertEqual(firstResult.first, .tiltBack)

        // Immediately try another tiltBack — should be within cooldown
        // First, settle the axis (need to drop below settling threshold)
        _ = detector.processAll((pitchRate: 0, rollRate: 0), at: now + 0.06)

        // Try to start a new gesture well within cooldown period
        let withinCooldown = now + 0.05 + cooldown * 0.5
        _ = detector.processAll((pitchRate: activationThreshold + 1.0, rollRate: 0), at: withinCooldown)
        _ = detector.processAll((pitchRate: minPeakVelocity + 2.0, rollRate: 0), at: withinCooldown + 0.01)
        let secondResult = detector.processAll(
            (pitchRate: completionVelocity, rollRate: 0),
            at: withinCooldown + 0.05
        )
        XCTAssertTrue(secondResult.isEmpty, "Gesture during same-direction cooldown should be rejected")
    }

    /// The opposite-direction cooldown is longer. A tiltForward immediately after
    /// tiltBack should be rejected within the opposite direction cooldown window.
    func testOppositeDirectionCooldownRejectsGesture() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureActivationThreshold
        let minPeakVelocity = Config.gestureMinPeakVelocity
        let oppositeCooldown = Config.gestureOppositeDirectionCooldown
        let normalCooldown = Config.gestureCooldown

        // Fire a tiltBack gesture (positive pitch)
        _ = detector.processAll((pitchRate: activationThreshold + 1.0, rollRate: 0), at: now)
        _ = detector.processAll((pitchRate: minPeakVelocity + 2.0, rollRate: 0), at: now + 0.01)
        let completionVelocity = (minPeakVelocity + 2.0) * Config.gestureCompletionRatio * 0.5
        let firstResult = detector.processAll((pitchRate: completionVelocity, rollRate: 0), at: now + 0.05)
        XCTAssertEqual(firstResult.first, .tiltBack, "First gesture should be tiltBack")

        // Settle the axis
        _ = detector.processAll((pitchRate: 0, rollRate: 0), at: now + 0.06)

        // Try opposite direction (negative pitch = tiltForward) after normal cooldown
        // but before opposite-direction cooldown expires
        let afterNormalCooldown = now + 0.05 + normalCooldown + 0.1
        XCTAssertTrue(afterNormalCooldown < now + 0.05 + oppositeCooldown,
            "Test precondition: time should be between normal and opposite cooldown")

        // Need to settle first — ensure velocity is below settling threshold and cooldown has elapsed
        _ = detector.processAll((pitchRate: 0, rollRate: 0), at: afterNormalCooldown - 0.01)

        _ = detector.processAll(
            (pitchRate: -(activationThreshold + 1.0), rollRate: 0),
            at: afterNormalCooldown
        )
        _ = detector.processAll(
            (pitchRate: -(minPeakVelocity + 2.0), rollRate: 0),
            at: afterNormalCooldown + 0.01
        )
        let reverseResult = detector.processAll(
            (pitchRate: -completionVelocity, rollRate: 0),
            at: afterNormalCooldown + 0.05
        )
        XCTAssertTrue(reverseResult.isEmpty,
            "Opposite-direction gesture should be rejected within opposite cooldown window")
    }

    /// After the full opposite-direction cooldown has elapsed, the opposite gesture fires.
    func testGestureFiresAfterOppositeDirectionCooldownExpires() {
        let now = CFAbsoluteTimeGetCurrent()
        let activationThreshold = Config.gestureActivationThreshold
        let minPeakVelocity = Config.gestureMinPeakVelocity
        let oppositeCooldown = Config.gestureOppositeDirectionCooldown

        // Fire a tiltBack gesture
        _ = detector.processAll((pitchRate: activationThreshold + 1.0, rollRate: 0), at: now)
        _ = detector.processAll((pitchRate: minPeakVelocity + 2.0, rollRate: 0), at: now + 0.01)
        let completionVelocity = (minPeakVelocity + 2.0) * Config.gestureCompletionRatio * 0.5
        let firstResult = detector.processAll((pitchRate: completionVelocity, rollRate: 0), at: now + 0.05)
        XCTAssertEqual(firstResult.first, .tiltBack)

        // Settle and wait beyond the opposite cooldown
        let afterFullCooldown = now + 0.05 + oppositeCooldown + 0.1
        _ = detector.processAll((pitchRate: 0, rollRate: 0), at: afterFullCooldown - 0.5)
        _ = detector.processAll((pitchRate: 0, rollRate: 0), at: afterFullCooldown - 0.01)

        // Now try the opposite direction — should succeed
        _ = detector.processAll(
            (pitchRate: -(activationThreshold + 1.0), rollRate: 0),
            at: afterFullCooldown
        )
        _ = detector.processAll(
            (pitchRate: -(minPeakVelocity + 2.0), rollRate: 0),
            at: afterFullCooldown + 0.01
        )
        let reverseResult = detector.processAll(
            (pitchRate: -completionVelocity, rollRate: 0),
            at: afterFullCooldown + 0.05
        )
        XCTAssertEqual(reverseResult.count, 1, "Opposite gesture should fire after full cooldown")
        XCTAssertEqual(reverseResult.first, .tiltForward)
    }
}
