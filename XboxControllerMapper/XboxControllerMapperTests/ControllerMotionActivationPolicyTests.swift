import XCTest
@testable import ControllerKeys

final class ControllerMotionActivationPolicyTests: XCTestCase {
    func testShouldEnableMotion_falseWhenControllerHasNoMotion() {
        let profile = Profile(name: "NoMotion")

        XCTAssertFalse(
            ControllerMotionActivationPolicy.shouldEnableMotion(
                profile: profile,
                hasMotion: false
            )
        )
    }

    func testShouldEnableMotion_falseWhenControllerHasMotionButNoFeaturesEnabled() {
        let profile = Profile(name: "NoMotion")

        XCTAssertFalse(
            ControllerMotionActivationPolicy.shouldEnableMotion(
                profile: profile,
                hasMotion: true
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
                hasMotion: true
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
                hasMotion: true
            )
        )
    }
}
