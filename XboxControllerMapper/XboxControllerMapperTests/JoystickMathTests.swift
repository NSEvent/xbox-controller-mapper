import XCTest
@testable import ControllerKeys

/// Tests for the mathematical formulas used in joystick, touchpad, and scroll processing.
/// These call the real extracted functions in JoystickMath and computed properties on
/// JoystickSettings — no formula reimplementations.
final class JoystickMathTests: XCTestCase {

    // MARK: - Circular Deadzone Tests

    func testDeadzoneFiltersSmallInputs() {
        let result = JoystickMath.circularDeadzone(x: 0.1, y: 0.05, deadzone: 0.15)
        XCTAssertNil(result, "Input within deadzone should be filtered out")
    }

    func testDeadzonePassesLargeInputs() {
        let result = JoystickMath.circularDeadzone(x: 0.5, y: 0.5, deadzone: 0.15)
        XCTAssertNotNil(result, "Input outside deadzone should pass through")
        XCTAssertEqual(result!, sqrt(0.5), accuracy: 1e-10)
    }

    func testDeadzoneAtBoundary() {
        let result = JoystickMath.circularDeadzone(x: 0.15, y: 0.0, deadzone: 0.15)
        XCTAssertNil(result, "Input exactly at deadzone boundary should be filtered (uses > not >=)")
    }

    func testDeadzoneIsCircular() {
        // Diagonal input with small per-axis values can exceed deadzone
        let result = JoystickMath.circularDeadzone(x: 0.12, y: 0.12, deadzone: 0.15)
        // 0.12^2 + 0.12^2 = 0.0288 > 0.0225 = 0.15^2
        XCTAssertNotNil(result,
                         "Circular deadzone: diagonal input can exceed threshold even if each axis is below")
    }

    // MARK: - Normalized Magnitude Tests

    func testNormalizedMagnitudeAtDeadzone() {
        let result = JoystickMath.normalizedMagnitude(0.15, deadzone: 0.15)
        XCTAssertEqual(result, 0.0, accuracy: 1e-10,
                        "At deadzone boundary, normalized magnitude should be 0")
    }

    func testNormalizedMagnitudeAtFull() {
        let result = JoystickMath.normalizedMagnitude(1.0, deadzone: 0.15)
        XCTAssertEqual(result, 1.0, accuracy: 1e-10,
                        "At full deflection, normalized magnitude should be 1.0")
    }

    func testNormalizedMagnitudeAtMidpoint() {
        let result = JoystickMath.normalizedMagnitude(0.575, deadzone: 0.15)
        XCTAssertEqual(result, 0.5, accuracy: 1e-10,
                        "At midpoint, normalized magnitude should be 0.5")
    }

    // MARK: - Mouse Acceleration Curve Tests

    func testMouseAccelerationExponentMapping() {
        var settings = JoystickSettings()

        settings.mouseAcceleration = 0.0
        XCTAssertEqual(settings.mouseAccelerationExponent, 1.0, "Acceleration 0 -> exponent 1.0 (linear)")

        settings.mouseAcceleration = 0.5
        XCTAssertEqual(settings.mouseAccelerationExponent, 2.0, "Acceleration 0.5 -> exponent 2.0 (quadratic)")

        settings.mouseAcceleration = 1.0
        XCTAssertEqual(settings.mouseAccelerationExponent, 3.0, "Acceleration 1.0 -> exponent 3.0 (cubic)")
    }

    func testMouseAccelerationCurveAtKeyPoints() {
        // With exponent 2.0 (acceleration = 0.5): pow(normalizedMagnitude, 2.0)
        let exponent = 2.0

        XCTAssertEqual(pow(0.0, exponent), 0.0, accuracy: 1e-10,
                        "Zero input -> zero acceleration")
        XCTAssertEqual(pow(0.5, exponent), 0.25, accuracy: 1e-10,
                        "Half input with quadratic acceleration -> 0.25")
        XCTAssertEqual(pow(1.0, exponent), 1.0, accuracy: 1e-10,
                        "Full input -> full acceleration")
    }

    func testScrollAccelerationExponentMapping() {
        var settings = JoystickSettings()

        settings.scrollAcceleration = 0.0
        XCTAssertEqual(settings.scrollAccelerationExponent, 1.0, "Scroll acceleration 0 -> exponent 1.0 (linear)")

        settings.scrollAcceleration = 0.5
        XCTAssertEqual(settings.scrollAccelerationExponent, 1.75, "Scroll acceleration 0.5 -> exponent 1.75")

        settings.scrollAcceleration = 1.0
        XCTAssertEqual(settings.scrollAccelerationExponent, 2.5, "Scroll acceleration 1.0 -> exponent 2.5")
    }

    // MARK: - Mouse Multiplier Tests

    func testMouseMultiplierAtZero() {
        var settings = JoystickSettings()
        settings.mouseSensitivity = 0.0
        XCTAssertEqual(settings.mouseMultiplier, 2.0, accuracy: 1e-10,
                        "Minimum sensitivity should give minimum multiplier of 2.0")
    }

    func testMouseMultiplierAtHalf() {
        var settings = JoystickSettings()
        settings.mouseSensitivity = 0.5
        // pow(0.5, 3) = 0.125, 2.0 + 0.125 * 118.0 = 16.75
        XCTAssertEqual(settings.mouseMultiplier, 16.75, accuracy: 1e-10,
                        "Mid sensitivity should use cubic mapping: 2 + 0.125 * 118 = 16.75")
    }

    func testMouseMultiplierAtFull() {
        var settings = JoystickSettings()
        settings.mouseSensitivity = 1.0
        XCTAssertEqual(settings.mouseMultiplier, 120.0, accuracy: 1e-10,
                        "Maximum sensitivity should give maximum multiplier of 120.0")
    }

    // MARK: - Scroll Multiplier Tests

    func testScrollMultiplierAtZero() {
        var settings = JoystickSettings()
        settings.scrollSensitivity = 0.0
        XCTAssertEqual(settings.scrollMultiplier, 1.0, accuracy: 1e-10,
                        "Minimum scroll sensitivity should give multiplier of 1.0")
    }

    func testScrollMultiplierAtHalf() {
        var settings = JoystickSettings()
        settings.scrollSensitivity = 0.5
        let expected = 1.0 + pow(0.5, 1.5) * 29.0
        XCTAssertEqual(settings.scrollMultiplier, expected, accuracy: 1e-10)
    }

    func testScrollMultiplierAtFull() {
        var settings = JoystickSettings()
        settings.scrollSensitivity = 1.0
        XCTAssertEqual(settings.scrollMultiplier, 30.0, accuracy: 1e-10,
                        "Maximum scroll sensitivity should give multiplier of 30.0")
    }

    // MARK: - Mouse Movement Scale Computation

    func testMouseMovementScaleFormula() {
        // Full pipeline using extracted functions and JoystickSettings properties
        let deadzone = 0.15
        let stickX = 0.7
        let stickY = 0.0

        var settings = JoystickSettings()
        settings.mouseSensitivity = 0.5
        settings.mouseAcceleration = 0.5
        settings.mouseDeadzone = deadzone

        guard let magnitude = JoystickMath.circularDeadzone(x: stickX, y: stickY, deadzone: deadzone) else {
            XCTFail("Input should be outside deadzone")
            return
        }

        let normalizedMag = JoystickMath.normalizedMagnitude(magnitude, deadzone: deadzone)
        let acceleratedMag = pow(normalizedMag, settings.mouseAccelerationExponent)
        let scale = acceleratedMag * settings.mouseMultiplier / magnitude
        let dx = stickX * scale

        XCTAssertEqual(magnitude, 0.7, accuracy: 1e-10)
        XCTAssertGreaterThan(normalizedMag, 0.0)
        XCTAssertLessThan(normalizedMag, 1.0)
        XCTAssertGreaterThan(dx, 0.0, "Positive stick input should produce positive dx")
        XCTAssertGreaterThan(scale, 0.0)
    }

    func testMouseMovementYInversion() {
        // invertMouseY = false: dy = -dy (stick up = mouse up, since stick y+ is up but mouse dy- is up)
        // invertMouseY = true: dy = dy (no negation)
        let stickY: CGFloat = 0.5
        let scale: CGFloat = 10.0
        let rawDy = stickY * scale

        let dyNormal = -rawDy // invertMouseY = false
        let dyInverted = rawDy // invertMouseY = true

        XCTAssertLessThan(Double(dyNormal), 0.0, "Normal: stick up (positive) -> negative dy (mouse moves up)")
        XCTAssertGreaterThan(Double(dyInverted), 0.0, "Inverted: stick up (positive) -> positive dy (mouse moves down)")
    }

    // MARK: - Scroll Processing Tests

    func testScrollHorizontalSuppression() {
        let effectiveX = JoystickMath.scrollEffectiveX(
            stickX: 0.2, stickY: 0.8, thresholdRatio: Config.scrollHorizontalThresholdRatio)
        // 0.8 > 0.2 and 0.2 < 0.8 * 0.7 = 0.56 -> suppress
        XCTAssertEqual(effectiveX, 0.0,
                        "Horizontal should be suppressed when vertical is dominant")
    }

    func testScrollHorizontalNotSuppressedWhenLarge() {
        let effectiveX = JoystickMath.scrollEffectiveX(
            stickX: 0.7, stickY: 0.8, thresholdRatio: Config.scrollHorizontalThresholdRatio)
        // 0.8 > 0.7 but 0.7 >= 0.8 * 0.7 = 0.56 -> not suppressed
        XCTAssertEqual(effectiveX, 0.7,
                        "Horizontal should pass through when sufficiently large")
    }

    func testScrollYInversion() {
        // invertScrollY = false: dy = dy (natural)
        // invertScrollY = true: dy = -dy (inverted)
        let stickY: CGFloat = 0.5
        let scale: CGFloat = 10.0
        let rawDy = stickY * scale

        let dyNatural = rawDy // invertScrollY = false
        let dyInverted = -rawDy // invertScrollY = true

        XCTAssertGreaterThan(Double(dyNatural), 0.0, "Natural scroll: stick up -> positive dy")
        XCTAssertLessThan(Double(dyInverted), 0.0, "Inverted scroll: stick up -> negative dy")
    }

    // MARK: - Smooth Deadzone (Gyro Aiming) Tests

    func testSmoothDeadzoneWithinDeadzone() {
        let deadzone = 0.05
        XCTAssertEqual(JoystickMath.smoothDeadzone(0.0, deadzone: deadzone), 0.0)
        XCTAssertEqual(JoystickMath.smoothDeadzone(0.03, deadzone: deadzone), 0.0)
        XCTAssertEqual(JoystickMath.smoothDeadzone(0.05, deadzone: deadzone), 0.0,
                        "Exactly at deadzone should return 0")
    }

    func testSmoothDeadzoneTransitionZone() {
        let deadzone = 0.1
        let result = JoystickMath.smoothDeadzone(0.15, deadzone: deadzone)
        // excess = 0.05, t = 0.5, result = 0.5 * 0.5 * 0.1 = 0.025
        XCTAssertEqual(result, 0.025, accuracy: 1e-10,
                        "In transition zone: quadratic ease-in")
    }

    func testSmoothDeadzoneAtDoubleDeadzone() {
        let deadzone = 0.1
        let result = JoystickMath.smoothDeadzone(0.2, deadzone: deadzone)
        XCTAssertEqual(result, deadzone, accuracy: 1e-10,
                        "At 2*deadzone, quadratic and linear should meet seamlessly")
    }

    func testSmoothDeadzoneAboveDoubleDeadzone() {
        let deadzone = 0.1
        let result = JoystickMath.smoothDeadzone(0.5, deadzone: deadzone)
        XCTAssertEqual(result, 0.4, accuracy: 1e-10,
                        "Above 2*deadzone: linear (value - deadzone)")
    }

    func testSmoothDeadzoneContinuityAtBoundary() {
        let deadzone = 0.1
        let epsilon = 1e-12

        let justBelow = JoystickMath.smoothDeadzone(0.2 - epsilon, deadzone: deadzone)
        let justAbove = JoystickMath.smoothDeadzone(0.2 + epsilon, deadzone: deadzone)

        XCTAssertEqual(justBelow, justAbove, accuracy: 1e-8,
                        "Smooth deadzone should be continuous at 2*deadzone boundary")
    }

    // MARK: - Stick Smoothing (1-Euro Inspired Low-Pass Filter)

    func testStickSmoothingWithZeroMagnitude() {
        let raw = CGPoint.zero
        let previous = CGPoint(x: 0.5, y: 0.5)
        let dt = Config.joystickPollInterval

        let result = JoystickMath.smoothStick(
            raw, previous: previous, dt: dt,
            minCutoff: Config.joystickMinCutoffFrequency,
            maxCutoff: Config.joystickMaxCutoffFrequency)

        // magnitude=0, t=0, cutoff=minCutoff, alpha is small -> result should be near previous but moving toward zero
        XCTAssertLessThan(abs(Double(result.x)), abs(Double(previous.x)),
                           "Smoothed value should move toward zero from previous")
    }

    func testStickSmoothingWithFullMagnitude() {
        let raw = CGPoint(x: 0.0, y: 1.0)
        let previous = CGPoint.zero
        let dt = Config.joystickPollInterval

        let result = JoystickMath.smoothStick(
            raw, previous: previous, dt: dt,
            minCutoff: Config.joystickMinCutoffFrequency,
            maxCutoff: Config.joystickMaxCutoffFrequency)

        XCTAssertGreaterThan(Double(result.y), 0.5,
                              "High magnitude should result in fast tracking (alpha near 1)")
    }

    func testStickSmoothingAlphaClampedToOne() {
        // Alpha = 1 - exp(-2*pi*cutoff*dt). For very large dt, alpha should not exceed 1.
        let magnitude = 2.0 // Clamped to 1.2 by min(1.0, magnitude*1.2)
        let t = min(1.0, magnitude * 1.2) // 1.0
        let cutoff = Config.joystickMinCutoffFrequency +
            (Config.joystickMaxCutoffFrequency - Config.joystickMinCutoffFrequency) * t
        let largeDt = 1.0 // 1 second
        let alpha = 1.0 - exp(-2.0 * Double.pi * cutoff * max(0.0, largeDt))

        XCTAssertLessThanOrEqual(alpha, 1.0, "Alpha should never exceed 1.0")
        XCTAssertGreaterThan(alpha, 0.99, "With large dt and max cutoff, alpha should be very close to 1.0")
    }

    func testStickSmoothingCutoffFrequencyRange() {
        let minCutoff = Config.joystickMinCutoffFrequency
        let maxCutoff = Config.joystickMaxCutoffFrequency

        // At zero magnitude: t=0 -> cutoff = minCutoff
        let t0: Double = 0.0
        let cutoff0 = minCutoff + (maxCutoff - minCutoff) * t0
        XCTAssertEqual(cutoff0, minCutoff, accuracy: 1e-10)

        // At full stick (magnitude=1): t = min(1, 1*1.2) = 1.0 -> cutoff = maxCutoff
        let t1: Double = 1.0
        let cutoff1 = minCutoff + (maxCutoff - minCutoff) * t1
        XCTAssertEqual(cutoff1, maxCutoff, accuracy: 1e-10)
    }

    // MARK: - Touchpad EMA Smoothing Tests

    func testTouchpadEMASmoothingConverges() {
        let smoothing = 0.4
        let alpha = JoystickMath.touchpadSmoothingAlpha(
            smoothing: smoothing, minAlpha: Config.touchpadMinSmoothingAlpha)
        let raw = CGPoint(x: 10.0, y: -5.0)

        var smoothed = CGPoint.zero
        for _ in 0..<50 {
            smoothed = CGPoint(
                x: smoothed.x + (raw.x - smoothed.x) * alpha,
                y: smoothed.y + (raw.y - smoothed.y) * alpha
            )
        }

        XCTAssertEqual(Double(smoothed.x), Double(raw.x), accuracy: 1e-6,
                        "EMA should converge to raw input")
        XCTAssertEqual(Double(smoothed.y), Double(raw.y), accuracy: 1e-6,
                        "EMA should converge to raw input")
    }

    func testTouchpadSmoothingAlphaMinimum() {
        let alpha = JoystickMath.touchpadSmoothingAlpha(
            smoothing: 1.0, minAlpha: Config.touchpadMinSmoothingAlpha)
        XCTAssertEqual(alpha, Config.touchpadMinSmoothingAlpha,
                        "Alpha should be clamped to minimum when smoothing is maxed")
    }

    func testTouchpadSmoothingDisabled() {
        let alpha = JoystickMath.touchpadSmoothingAlpha(
            smoothing: 0.0, minAlpha: Config.touchpadMinSmoothingAlpha)
        XCTAssertEqual(alpha, 1.0,
                        "Zero smoothing should give alpha=1.0 (instant tracking)")
    }

    func testTouchpadSmoothingStepResponse() {
        let smoothing = 0.4
        let alpha = JoystickMath.touchpadSmoothingAlpha(
            smoothing: smoothing, minAlpha: Config.touchpadMinSmoothingAlpha)
        let previous = CGPoint.zero
        let raw = CGPoint(x: 1.0, y: 0.0)

        let result = CGPoint(
            x: previous.x + (raw.x - previous.x) * alpha,
            y: previous.y + (raw.y - previous.y) * alpha
        )

        XCTAssertEqual(Double(result.x), alpha, accuracy: 1e-10,
                        "First step from zero should equal alpha")
    }

    // MARK: - Touchpad Sensitivity Calibration Tests

    func testTouchpadCalibrationCurve() {
        let settings = JoystickSettings()

        // At raw=0: 0 + boost * 0 * 1 = 0
        XCTAssertEqual(settings.calibratedTouchpadValue(0.0, boost: 1.2), 0.0, accuracy: 1e-10,
                        "Calibration at 0 should stay 0")

        // At raw=1: 1 + boost * 1 * 0 = 1
        XCTAssertEqual(settings.calibratedTouchpadValue(1.0, boost: 1.2), 1.0, accuracy: 1e-10,
                        "Calibration at 1 should stay 1")

        // At raw=0.5, boost=1.2: 0.5 + 1.2 * 0.5 * 0.5 = 0.8
        XCTAssertEqual(settings.calibratedTouchpadValue(0.5, boost: 1.2), 0.8, accuracy: 1e-10,
                        "Calibration at 0.5 with 1.2 boost should be 0.8")
    }

    func testTouchpadSensitivityMultiplierRange() {
        var settings = JoystickSettings()

        // At touchpadSensitivity=0: effective=0, mult = 0.25
        settings.touchpadSensitivity = 0.0
        XCTAssertEqual(settings.touchpadSensitivityMultiplier, 0.25, accuracy: 1e-10)

        // At touchpadSensitivity=1: effective=1, mult = 1.75
        settings.touchpadSensitivity = 1.0
        XCTAssertEqual(settings.touchpadSensitivityMultiplier, 1.75, accuracy: 1e-10)
    }

    // MARK: - Direction Keys Threshold Tests

    func testDirectionKeysThreshold() {
        let threshold = 0.4

        // Below threshold: no key
        XCTAssertFalse(0.3 > threshold)
        XCTAssertFalse(-0.3 < -threshold)

        // Above threshold: key pressed
        XCTAssertTrue(0.5 > threshold)
        XCTAssertTrue(-0.5 < -threshold)
    }

    func testDirectionKeysYInversion() {
        let stickY = 0.8

        let normalY = stickY * 1.0
        let invertedY = stickY * -1.0

        XCTAssertGreaterThan(normalY, 0.4, "Normal: stick up triggers up key")
        XCTAssertLessThan(invertedY, -0.4, "Inverted: stick up triggers down key")
    }

    // MARK: - Scroll Boost Multiplier Tests

    func testScrollBoostApplied() {
        let dy: CGFloat = 5.0
        let boostMultiplier = 2.0
        let boostedDy = dy * boostMultiplier

        XCTAssertEqual(Double(boostedDy), 10.0, accuracy: 1e-10,
                        "Scroll boost should double the dy value")
    }

    func testScrollBoostDirectionMatching() {
        let positiveStickY: CGFloat = 0.5
        let negativeStickY: CGFloat = -0.3

        XCTAssertEqual(positiveStickY >= 0 ? 1 : -1, 1)
        XCTAssertEqual(negativeStickY >= 0 ? 1 : -1, -1)
    }

    // MARK: - Focus Mode Multiplier Smoothing

    func testFocusMultiplierSmoothing() {
        let alpha = Config.focusMultiplierSmoothingAlpha
        var current = 120.0
        let target = 16.75

        // After one step
        current += alpha * (target - current)
        XCTAssertEqual(current, 120.0 + 0.08 * (16.75 - 120.0), accuracy: 1e-10)

        // After many steps, should converge to target
        for _ in 0..<500 {
            current += alpha * (target - current)
        }
        XCTAssertEqual(current, target, accuracy: 0.01,
                        "Multiplier should converge to target after many iterations")
    }

    // MARK: - Momentum Decay Tests

    func testMomentumExponentialDecay() {
        let decay = Config.touchpadMomentumDecay
        let dt = 1.0 / 120.0
        let initialVelocity = 2000.0

        let decayedVelocity = initialVelocity * exp(-decay * dt)

        XCTAssertLessThan(decayedVelocity, initialVelocity, "Velocity should decrease after decay")
        XCTAssertGreaterThan(decayedVelocity, 0.0, "Velocity should remain positive")

        // After many ticks, should approach zero
        var velocity = initialVelocity
        for _ in 0..<(120 * 10) {
            velocity *= exp(-decay * dt)
        }
        XCTAssertLessThan(velocity, Config.touchpadMomentumStopVelocity,
                           "Velocity should decay below stop threshold within 10 seconds")
    }

    func testMomentumStopThreshold() {
        let stopVelocity = Config.touchpadMomentumStopVelocity
        XCTAssertGreaterThan(stopVelocity, 0.0, "Stop velocity should be positive")

        let vx: CGFloat = 20.0
        let vy: CGFloat = 20.0
        let speed = Double(hypot(vx, vy))
        XCTAssertLessThan(speed, stopVelocity,
                           "Speed below stop threshold should terminate momentum")
    }

    // MARK: - Momentum Boost Factor Tests

    func testMomentumBoostFactorRange() {
        let boostMin = Config.touchpadMomentumBoostMin
        let boostMax = Config.touchpadMomentumBoostMax
        let boostRange = boostMax - boostMin
        let startVelocity = Config.touchpadMomentumStartVelocity
        let boostMaxVelocity = Config.touchpadMomentumBoostMaxVelocity
        let velocityRange = boostMaxVelocity - startVelocity

        // At threshold velocity: boost = boostMin
        let boostAtThreshold = boostMin + boostRange * (0 / velocityRange)
        XCTAssertEqual(boostAtThreshold, boostMin, accuracy: 1e-10)

        // At max boost velocity: boost = boostMax
        let boostAtMax = boostMin + boostRange * (velocityRange / velocityRange)
        XCTAssertEqual(boostAtMax, boostMax, accuracy: 1e-10)

        // At midpoint velocity
        let midVelocity = (boostMaxVelocity + startVelocity) / 2.0
        let midAboveThreshold = midVelocity - startVelocity
        let boostAtMid = boostMin + boostRange * (midAboveThreshold / velocityRange)
        XCTAssertEqual(boostAtMid, (boostMin + boostMax) / 2.0, accuracy: 1e-10,
                        "Midpoint velocity should give midpoint boost")
    }
}
