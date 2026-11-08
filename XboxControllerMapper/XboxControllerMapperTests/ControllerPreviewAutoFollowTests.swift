import XCTest
@testable import ControllerKeys

final class ControllerPreviewAutoFollowTests: XCTestCase {
	func testFreshPressSelectsEverySupportedControllerFamily() {
		for layout in ControllerPreviewLayout.concreteLayouts {
			var follow = ControllerPreviewAutoFollow()
			XCTAssertEqual(follow.receive(buttons: [.a], isConnected: true,
				activeDescriptor: ControllerVisualDescriptor.concrete(for: layout)!), layout)
		}
	}

	func testPressOnAnotherControllerReplacesManualPreview() {
		var follow = ControllerPreviewAutoFollow()
		let xbox = ControllerVisualDescriptor(family: .xbox)
		let playStation = ControllerVisualDescriptor(family: .dualSense)
		XCTAssertEqual(follow.receive(buttons: [.a], isConnected: true, activeDescriptor: xbox), .xbox)
		XCTAssertNil(follow.receive(buttons: [], isConnected: true, activeDescriptor: xbox))
		XCTAssertEqual(follow.receive(buttons: [.b], isConnected: true, activeDescriptor: playStation), .dualSense)
	}

	func testIdleConnectionChangeDoesNotChangePreview() {
		var follow = ControllerPreviewAutoFollow()
		for layout in ControllerPreviewLayout.concreteLayouts {
			XCTAssertNil(follow.receive(buttons: [], isConnected: true,
				activeDescriptor: ControllerVisualDescriptor.concrete(for: layout)!))
		}
	}

	func testHeldButtonAndReleaseDoNotOverrideManualSelection() {
		var follow = ControllerPreviewAutoFollow()
		let descriptor = ControllerVisualDescriptor(family: .dualSense)
		XCTAssertEqual(follow.receive(buttons: [.a], isConnected: true, activeDescriptor: descriptor), .dualSense)
		// A user can now pick Xbox manually. Repeated held state must not undo it.
		XCTAssertNil(follow.receive(buttons: [.a], isConnected: true, activeDescriptor: descriptor))
		XCTAssertNil(follow.receive(buttons: [], isConnected: true, activeDescriptor: descriptor))
		XCTAssertEqual(follow.receive(buttons: [.a], isConnected: true, activeDescriptor: descriptor), .dualSense)
	}

	func testAdditionalChordMemberIsFreshInputButPartialReleaseIsNot() {
		var follow = ControllerPreviewAutoFollow()
		let descriptor = ControllerVisualDescriptor(family: .nintendo)
		_ = follow.receive(buttons: [.a], isConnected: true, activeDescriptor: descriptor)
		XCTAssertEqual(follow.receive(buttons: [.a, .b], isConnected: true, activeDescriptor: descriptor), .nintendo)
		XCTAssertNil(follow.receive(buttons: [.b], isConnected: true, activeDescriptor: descriptor))
	}

	func testDisconnectedInputDoesNotSelectRememberedController() {
		var follow = ControllerPreviewAutoFollow()
		let descriptor = ControllerVisualDescriptor(family: .steam)
		XCTAssertNil(follow.receive(buttons: [.a], isConnected: false, activeDescriptor: descriptor))
		XCTAssertNil(follow.receive(buttons: [], isConnected: false, activeDescriptor: descriptor))
		XCTAssertEqual(follow.receive(buttons: [.a], isConnected: true, activeDescriptor: descriptor), .steam)
	}
	func testGestureNoiseDoesNotSwitchButPhysicalButtonAlongsideItDoes() {
		var follow = ControllerPreviewAutoFollow()
		let descriptor = ControllerVisualDescriptor(family: .dualSense)
		XCTAssertNil(follow.receive(buttons: [.gestureTiltBack, .leftStickUp], isConnected: true, activeDescriptor: descriptor))
		XCTAssertEqual(follow.receive(buttons: [.gestureTiltBack, .a], isConnected: true, activeDescriptor: descriptor), .dualSense)
	}

}
