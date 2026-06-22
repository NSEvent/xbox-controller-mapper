import CoreGraphics
import XCTest
@testable import ControllerKeys

final class ControllerInputEventTests: XCTestCase {
	func testDiscreteInputEventsUseInputQueue() {
		let events: [ControllerInputEvent] = [
			.buttonPressed(.a),
			.buttonReleased(.a, holdDuration: 0.12),
			.chordDetected([.a, .b]),
			.controllerButtonTap(.touchpadButton),
			.touchpadRegionTap(.topLeft),
			.motionGesture(.tiltBack)
		]

		for event in events {
			XCTAssertEqual(ControllerInputEventRouting.queue(for: event), .input, "\(event) should use inputQueue")
		}
	}

	func testContinuousTouchpadEventsUsePollingQueue() {
		let gesture = TouchpadGesture(
			centerDelta: CGPoint(x: 1, y: 2),
			distanceDelta: 3,
			isPrimaryTouching: true,
			isSecondaryTouching: true
		)
		let events: [ControllerInputEvent] = [
			.touchpadMoved(CGPoint(x: 1, y: 1)),
			.steamLeftTouchpadMoved(CGPoint(x: -1, y: 0.5)),
			.appleTVRemoteCircularScroll(0.25),
			.touchpadGesture(gesture),
			.touchpadTap,
			.touchpadTwoFingerTap,
			.touchpadLongTap,
			.touchpadTwoFingerLongTap
		]

		for event in events {
			XCTAssertEqual(ControllerInputEventRouting.queue(for: event), .polling, "\(event) should use pollingQueue")
		}
	}
}
