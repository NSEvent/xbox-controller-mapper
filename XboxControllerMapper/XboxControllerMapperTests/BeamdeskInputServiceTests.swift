import XCTest
@testable import ControllerKeys

final class BeamdeskInputServiceTests: XCTestCase {
    func testEveryNotificationIDMapsToOneDistinctControllerButton() {
        let buttons = Set(BeamdeskHandInput.allCases.map(\.button))

        XCTAssertEqual(BeamdeskHandInput.allCases.count, 10)
        XCTAssertEqual(buttons.count, 10)
        XCTAssertEqual(buttons, Set(ControllerButton.beamdeskHandButtons))
    }

    func testParsesPressAndRelease() {
        XCTAssertEqual(
            BeamdeskInputEvent(
                notificationID: "controllerkeys.beamdesk-hand.left.swipe-forward",
                argument: "pressed"
            ),
            BeamdeskInputEvent(input: .leftSwipeForward, phase: .pressed)
        )
        XCTAssertEqual(
            BeamdeskInputEvent(
                notificationID: "controllerkeys.beamdesk-hand.right.thumb-tap",
                argument: "released"
            ),
            BeamdeskInputEvent(input: .rightThumbTap, phase: .released)
        )
    }

    func testRejectsUnknownIDsAndPhases() {
        XCTAssertNil(
            BeamdeskInputEvent(
                notificationID: "controllerkeys.beamdesk-hand.middle.thumb-tap",
                argument: "pressed"
            )
        )
        XCTAssertNil(
            BeamdeskInputEvent(
                notificationID: "controllerkeys.beamdesk-hand.left.thumb-tap",
                argument: "tap"
            )
        )
        XCTAssertNil(
            BeamdeskInputEvent(
                notificationID: "controllerkeys.beamdesk-hand.left.thumb-tap",
                argument: nil
            )
        )
    }

	func testCooldownRejectsSecondRecognitionFromSameHand() {
		var cooldown = BeamdeskGestureCooldown()

		XCTAssertTrue(cooldown.accepts(.leftSwipeLeft, at: 10))
		XCTAssertFalse(cooldown.accepts(.leftSwipeRight, at: 10.64))
	}

	func testCooldownAllowsSimultaneousOppositeHandGesture() {
		var cooldown = BeamdeskGestureCooldown()

		XCTAssertTrue(cooldown.accepts(.leftThumbTap, at: 10))
		XCTAssertTrue(cooldown.accepts(.rightThumbTap, at: 10))
	}

	func testCooldownAllowsSameHandAfterWindow() {
		var cooldown = BeamdeskGestureCooldown()

		XCTAssertTrue(cooldown.accepts(.rightSwipeForward, at: 10))
		XCTAssertTrue(
			cooldown.accepts(
				.rightSwipeBack,
				at: 10 + BeamdeskGestureCooldown.defaultDuration
			)
		)
	}
}

private extension BeamdeskInputEvent {
    init(input: BeamdeskHandInput, phase: BeamdeskInputPhase) {
        self.init(notificationID: input.rawValue, argument: phase.rawValue)!
    }
}
