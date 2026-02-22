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

    /// The process() method returns only the first result.
    func testProcessReturnsSingleResult() {
        let now = CFAbsoluteTimeGetCurrent()
        let result = detector.process((pitchRate: 0, rollRate: 0), at: now)
        XCTAssertNil(result, "No gesture for zero velocity")
    }
}
