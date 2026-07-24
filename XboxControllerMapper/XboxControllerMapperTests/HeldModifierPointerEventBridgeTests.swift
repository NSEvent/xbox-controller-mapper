import CoreGraphics
import XCTest
@testable import ControllerKeys

final class HeldModifierPointerEventBridgePolicyTests: XCTestCase {
	func testPointerAndTabletEventsAreAugmented() {
		let expected: Set<CGEventType> = [
			.leftMouseDown,
			.leftMouseUp,
			.rightMouseDown,
			.rightMouseUp,
			.mouseMoved,
			.leftMouseDragged,
			.rightMouseDragged,
			.scrollWheel,
			.tabletPointer,
			.otherMouseDown,
			.otherMouseUp,
			.otherMouseDragged
		]

		XCTAssertEqual(Set(HeldModifierPointerEventPolicy.eventTypes), expected)
		for type in expected {
			XCTAssertTrue(HeldModifierPointerEventPolicy.shouldAugment(type))
		}
	}

	func testKeyboardEventsAreNotAugmented() {
		for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
			XCTAssertFalse(HeldModifierPointerEventPolicy.shouldAugment(type))
		}
	}

	func testHeldShiftIsAddedToWacomLikePointerEvent() {
		let flags = HeldModifierPointerEventPolicy.augmentedFlags(
			eventFlags: [],
			heldModifiers: [.maskShift]
		)

		XCTAssertTrue(flags.contains(.maskShift))
	}

	func testExistingPhysicalModifiersArePreserved() {
		let flags = HeldModifierPointerEventPolicy.augmentedFlags(
			eventFlags: [.maskCommand, .maskNonCoalesced],
			heldModifiers: [.maskShift]
		)

		XCTAssertTrue(flags.contains(.maskCommand))
		XCTAssertTrue(flags.contains(.maskShift))
		XCTAssertTrue(flags.contains(.maskNonCoalesced))
	}
}
