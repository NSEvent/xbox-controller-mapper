import XCTest
import CoreGraphics
@testable import ControllerKeys

final class ControllerInputEventTests: XCTestCase {

    func testButtonPressedEquality() {
        let event1 = ControllerInputEvent.buttonPressed(.a)
        let event2 = ControllerInputEvent.buttonPressed(.a)
        let event3 = ControllerInputEvent.buttonPressed(.b)

        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }

    func testButtonReleasedEquality() {
        let event1 = ControllerInputEvent.buttonReleased(.a, holdDuration: 0.5)
        let event2 = ControllerInputEvent.buttonReleased(.a, holdDuration: 0.5)
        let event3 = ControllerInputEvent.buttonReleased(.a, holdDuration: 1.0)

        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }

    func testChordEquality() {
        let event1 = ControllerInputEvent.chord(buttons: [.a, .b])
        let event2 = ControllerInputEvent.chord(buttons: [.a, .b])
        let event3 = ControllerInputEvent.chord(buttons: [.a, .x])

        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }

    func testTouchpadMovedEquality() {
        let event1 = ControllerInputEvent.touchpadMoved(delta: CGPoint(x: 1.0, y: 2.0))
        let event2 = ControllerInputEvent.touchpadMoved(delta: CGPoint(x: 1.0, y: 2.0))
        let event3 = ControllerInputEvent.touchpadMoved(delta: CGPoint(x: 3.0, y: 4.0))

        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }

    func testTouchpadGestureEquality() {
        let gesture1 = TouchpadGesture(centerDelta: .zero, distanceDelta: 0.5, isPrimaryTouching: true, isSecondaryTouching: true)
        let gesture2 = TouchpadGesture(centerDelta: .zero, distanceDelta: 0.5, isPrimaryTouching: true, isSecondaryTouching: true)
        let gesture3 = TouchpadGesture(centerDelta: .zero, distanceDelta: 1.0, isPrimaryTouching: true, isSecondaryTouching: true)

        XCTAssertEqual(
            ControllerInputEvent.touchpadGesture(gesture1),
            ControllerInputEvent.touchpadGesture(gesture2)
        )
        XCTAssertNotEqual(
            ControllerInputEvent.touchpadGesture(gesture1),
            ControllerInputEvent.touchpadGesture(gesture3)
        )
    }

    func testMotionGestureEquality() {
        let event1 = ControllerInputEvent.motionGesture(.tiltBack)
        let event2 = ControllerInputEvent.motionGesture(.tiltBack)
        let event3 = ControllerInputEvent.motionGesture(.steerLeft)

        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }

    func testTapEventsEquality() {
        XCTAssertEqual(ControllerInputEvent.touchpadTap, ControllerInputEvent.touchpadTap)
        XCTAssertEqual(ControllerInputEvent.touchpadTwoFingerTap, ControllerInputEvent.touchpadTwoFingerTap)
        XCTAssertEqual(ControllerInputEvent.touchpadLongTap, ControllerInputEvent.touchpadLongTap)
        XCTAssertEqual(ControllerInputEvent.touchpadTwoFingerLongTap, ControllerInputEvent.touchpadTwoFingerLongTap)
    }

    func testButtonReleasedCrossButtonInequality() {
        let releaseA = ControllerInputEvent.buttonReleased(.a, holdDuration: 0.5)
        let releaseB = ControllerInputEvent.buttonReleased(.b, holdDuration: 0.5)

        XCTAssertNotEqual(releaseA, releaseB,
            "buttonReleased events for different buttons should not be equal even with same holdDuration")
    }

    func testDifferentEventTypesNotEqual() {
        let button = ControllerInputEvent.buttonPressed(.a)
        let tap = ControllerInputEvent.touchpadTap
        let motion = ControllerInputEvent.motionGesture(.tiltBack)

        XCTAssertNotEqual(button, tap)
        XCTAssertNotEqual(button, motion)
        XCTAssertNotEqual(tap, motion)
    }
}
