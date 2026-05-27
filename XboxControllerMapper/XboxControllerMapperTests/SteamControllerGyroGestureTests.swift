import XCTest
@testable import ControllerKeys

final class SteamControllerGyroGestureTests: XCTestCase {
    func testGestureGyroScaleUsesRawSensorRange() {
        let oneFullScaleAxis = 32768.0
        let gestureRate = ControllerService.steamGyroRotationRate(
            counts: oneFullScaleAxis,
            multiplier: Config.steamGyroGestureSensitivityMultiplier
        )
        let aimingRate = ControllerService.steamGyroRotationRate(
            counts: oneFullScaleAxis,
            multiplier: Config.steamGyroAimingSensitivityMultiplier
        )

        XCTAssertEqual(gestureRate, 2000.0 * Double.pi / 180.0, accuracy: 0.001)
        XCTAssertGreaterThan(gestureRate / aimingRate, 2.7)
    }

    func testGestureScaleLetsPitchSnapsTriggerBothDirections() {
        let aimingPeak = ControllerService.steamGyroRotationRate(
            counts: 7_000,
            multiplier: Config.steamGyroAimingSensitivityMultiplier
        )
        XCTAssertLessThan(aimingPeak, Config.gestureActivationThreshold)

        assertPitchSnap(sign: 1, expected: .tiltBack)
        assertPitchSnap(sign: -1, expected: .tiltForward)
    }

    func testGestureScaleLetsSteerSnapsTriggerBothDirections() {
        let aimingPeak = ControllerService.steamGyroRotationRate(
            counts: 5_000,
            multiplier: Config.steamGyroAimingSensitivityMultiplier
        )
        XCTAssertLessThan(aimingPeak, Config.gestureRollActivationThreshold)

        assertSteerSnap(sign: 1, expected: .steerLeft)
        assertSteerSnap(sign: -1, expected: .steerRight)
    }

    private func assertPitchSnap(sign: Double, expected: MotionGestureType) {
        let detector = MotionGestureDetector()
        let now = CFAbsoluteTimeGetCurrent()
        let start = steamGestureRate(counts: 5_000) * sign
        let peak = steamGestureRate(counts: 7_000) * sign
        let completion = peak * Config.gestureCompletionRatio * 0.5

        _ = detector.processAll((pitchRate: start, rollRate: 0), at: now)
        _ = detector.processAll((pitchRate: peak, rollRate: 0), at: now + 0.01)
        let results = detector.processAll((pitchRate: completion, rollRate: 0), at: now + 0.05)

        XCTAssertEqual(results.first, expected)
    }

    private func assertSteerSnap(sign: Double, expected: MotionGestureType) {
        let detector = MotionGestureDetector()
        let now = CFAbsoluteTimeGetCurrent()
        let start = steamGestureRate(counts: 3_500) * sign
        let peak = steamGestureRate(counts: 5_000) * sign
        let completion = peak * Config.gestureCompletionRatio * 0.5

        _ = detector.processAll((pitchRate: 0, rollRate: start), at: now)
        _ = detector.processAll((pitchRate: 0, rollRate: peak), at: now + 0.01)
        let results = detector.processAll((pitchRate: 0, rollRate: completion), at: now + 0.05)

        XCTAssertEqual(results.first, expected)
    }

    private func steamGestureRate(counts: Double) -> Double {
        ControllerService.steamGyroRotationRate(
            counts: counts,
            multiplier: Config.steamGyroGestureSensitivityMultiplier
        )
    }
}
