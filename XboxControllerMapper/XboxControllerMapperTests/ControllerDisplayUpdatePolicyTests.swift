import XCTest
import CoreGraphics
@testable import ControllerKeys

final class ControllerDisplayUpdatePolicyTests: XCTestCase {
    func testResolveAlwaysUpdatesRawState() {
        let current = makeState(
            leftStick: .zero,
            rightStick: .zero,
            leftTriggerValue: 0,
            rightTriggerValue: 0
        )
        let sample = makeSample(
            leftStick: CGPoint(x: 0.4, y: -0.2),
            rightStick: CGPoint(x: -0.5, y: 0.9),
            leftTrigger: 0.7,
            rightTrigger: 0.8
        )

        let result = ControllerDisplayUpdatePolicy.resolve(
            current: current,
            sample: sample,
            deadzone: 0.15
        )

        XCTAssertEqual(result.leftStick, sample.leftStick)
        XCTAssertEqual(result.rightStick, sample.rightStick)
        XCTAssertEqual(result.leftTriggerValue, sample.leftTrigger)
        XCTAssertEqual(result.rightTriggerValue, sample.rightTrigger)
    }

    func testResolveUpdatesStickDisplayOnlyWhenDeadzoneExceeded() {
        let current = makeState(
            displayLeftStick: CGPoint(x: 0.10, y: 0.10),
            displayRightStick: CGPoint(x: 0.30, y: 0.30)
        )
        let sample = makeSample(
            leftStick: CGPoint(x: 0.20, y: 0.18),   // delta within deadzone
            rightStick: CGPoint(x: 0.60, y: 0.20)   // x delta exceeds deadzone
        )

        let result = ControllerDisplayUpdatePolicy.resolve(
            current: current,
            sample: sample,
            deadzone: 0.15
        )

        XCTAssertEqual(result.displayLeftStick, current.displayLeftStick)
        XCTAssertEqual(result.displayRightStick, sample.rightStick)
    }

    func testResolveUpdatesTriggerDisplayOnlyWhenDeadzoneExceeded() {
        let current = makeState(
            displayLeftTrigger: 0.40,
            displayRightTrigger: 0.20
        )
        let sample = makeSample(
            leftTrigger: 0.49,   // within 0.15 deadzone
            rightTrigger: 0.40   // exceeds deadzone
        )

        let result = ControllerDisplayUpdatePolicy.resolve(
            current: current,
            sample: sample,
            deadzone: 0.15
        )

        XCTAssertEqual(result.displayLeftTrigger, current.displayLeftTrigger)
        XCTAssertEqual(result.displayRightTrigger, sample.rightTrigger)
    }

    func testResolveUpdatesTouchpadDisplayWhenValuesChange() {
        let current = makeState(
            displayTouchpadPosition: .zero,
            displayTouchpadSecondaryPosition: .zero,
            displayIsTouchpadTouching: false,
            displayIsTouchpadSecondaryTouching: false
        )
        let sample = makeSample(
            touchpadPosition: CGPoint(x: 0.2, y: 0.3),
            touchpadSecondaryPosition: CGPoint(x: 0.7, y: 0.6),
            isTouchpadTouching: true,
            isTouchpadSecondaryTouching: true
        )

        let result = ControllerDisplayUpdatePolicy.resolve(
            current: current,
            sample: sample,
            deadzone: 0.15
        )

        XCTAssertEqual(result.displayTouchpadPosition, sample.touchpadPosition)
        XCTAssertEqual(result.displayTouchpadSecondaryPosition, sample.touchpadSecondaryPosition)
        XCTAssertEqual(result.displayIsTouchpadTouching, sample.isTouchpadTouching)
        XCTAssertEqual(result.displayIsTouchpadSecondaryTouching, sample.isTouchpadSecondaryTouching)
    }

    private func makeState(
        leftStick: CGPoint = .zero,
        rightStick: CGPoint = .zero,
        leftTriggerValue: Float = 0,
        rightTriggerValue: Float = 0,
        displayLeftStick: CGPoint = .zero,
        displayRightStick: CGPoint = .zero,
        displayLeftTrigger: Float = 0,
        displayRightTrigger: Float = 0,
        displayTouchpadPosition: CGPoint = .zero,
        displayTouchpadSecondaryPosition: CGPoint = .zero,
        displayIsTouchpadTouching: Bool = false,
        displayIsTouchpadSecondaryTouching: Bool = false
    ) -> ControllerDisplayState {
        ControllerDisplayState(
            leftStick: leftStick,
            rightStick: rightStick,
            leftTriggerValue: leftTriggerValue,
            rightTriggerValue: rightTriggerValue,
            displayLeftStick: displayLeftStick,
            displayRightStick: displayRightStick,
            displayLeftTrigger: displayLeftTrigger,
            displayRightTrigger: displayRightTrigger,
            displayTouchpadPosition: displayTouchpadPosition,
            displayTouchpadSecondaryPosition: displayTouchpadSecondaryPosition,
            displayIsTouchpadTouching: displayIsTouchpadTouching,
            displayIsTouchpadSecondaryTouching: displayIsTouchpadSecondaryTouching
        )
    }

    private func makeSample(
        leftStick: CGPoint = .zero,
        rightStick: CGPoint = .zero,
        leftTrigger: Float = 0,
        rightTrigger: Float = 0,
        touchpadPosition: CGPoint = .zero,
        touchpadSecondaryPosition: CGPoint = .zero,
        isTouchpadTouching: Bool = false,
        isTouchpadSecondaryTouching: Bool = false
    ) -> ControllerDisplaySample {
        ControllerDisplaySample(
            leftStick: leftStick,
            rightStick: rightStick,
            leftTrigger: leftTrigger,
            rightTrigger: rightTrigger,
            touchpadPosition: touchpadPosition,
            touchpadSecondaryPosition: touchpadSecondaryPosition,
            isTouchpadTouching: isTouchpadTouching,
            isTouchpadSecondaryTouching: isTouchpadSecondaryTouching
        )
    }
}
