import XCTest
@testable import ControllerKeys

final class ControllerMotionActivationPolicyTests: XCTestCase {
    func testShouldEnableMotion_falseWhenNotDualSense() {
        let profile = Profile(name: "NoMotion")

        XCTAssertFalse(
            ControllerMotionActivationPolicy.shouldEnableMotion(
                profile: profile,
                isDualSense: false
            )
        )
    }

    func testShouldEnableMotion_falseWhenDualSenseHasNoMotionFeaturesEnabled() {
        let profile = Profile(name: "NoMotion")

        XCTAssertFalse(
            ControllerMotionActivationPolicy.shouldEnableMotion(
                profile: profile,
                isDualSense: true
            )
        )
    }

    func testShouldEnableMotion_trueWhenGyroAimingEnabled() {
        var settings = JoystickSettings.default
        settings.gyroAimingEnabled = true
        let profile = Profile(name: "Gyro", joystickSettings: settings)

        XCTAssertTrue(
            ControllerMotionActivationPolicy.shouldEnableMotion(
                profile: profile,
                isDualSense: true
            )
        )
    }

    func testShouldEnableMotion_trueWhenGestureMappingHasAction() {
        let profile = Profile(
            name: "Gestures",
            gestureMappings: [
                GestureMapping(gestureType: .tiltBack, keyCode: 12)
            ]
        )

        XCTAssertTrue(
            ControllerMotionActivationPolicy.shouldEnableMotion(
                profile: profile,
                isDualSense: true
            )
        )
    }
}
