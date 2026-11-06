import XCTest
import CoreGraphics
@testable import ControllerKeys

final class HeldOutputRoutesTests: XCTestCase {
	private let command = CGEventFlags.maskCommand.rawValue

	func testKeyReleaseFollowsPressRouteAcrossHandoff() {
		var routes = HeldOutputRoutes()
		routes.keyPressed(13, route: .local)
		routes.keyPressed(14, route: .remote)

		XCTAssertEqual(routes.keyReleased(13), .local, "a key pressed here must be released here after handoff")
		XCTAssertEqual(routes.keyReleased(14), .remote, "a key pressed on the peer must be released on the peer after return")
		XCTAssertNil(routes.keyReleased(13))
	}

	func testLocalModifierReleasesLocallyWhileRelaying() {
		var routes = HeldOutputRoutes()
		// Cmd held locally before handoff: total count 1, no remote holds.
		XCTAssertEqual(routes.modifierReleaseRoute(mask: command, totalCount: 1, relaying: true), .local)
	}

	func testRemoteModifierReleasesOnPeerAfterReturn() {
		var routes = HeldOutputRoutes()
		routes.modifierPressedRemotely(mask: command)
		XCTAssertEqual(routes.modifierReleaseRoute(mask: command, totalCount: 1, relaying: false), .remote)
		XCTAssertEqual(routes.remoteModifierCount(mask: command), 0)
	}

	func testMixedModifierHoldsDrainBothRoutes() {
		var routes = HeldOutputRoutes()
		routes.modifierPressedRemotely(mask: command)
		// One local and one remote hold of Cmd, cursor back on this Mac.
		XCTAssertEqual(routes.modifierReleaseRoute(mask: command, totalCount: 2, relaying: false), .local)
		XCTAssertEqual(routes.modifierReleaseRoute(mask: command, totalCount: 1, relaying: false), .remote)
	}

	func testUnknownReleaseKeepsCurrentRoute() {
		var routes = HeldOutputRoutes()
		XCTAssertEqual(routes.modifierReleaseRoute(mask: command, totalCount: 0, relaying: true), .remote)
		XCTAssertEqual(routes.modifierReleaseRoute(mask: command, totalCount: 0, relaying: false), .local)
	}

	func testTakeRemoteHoldsReturnsAndForgetsOnlyRemote() {
		var routes = HeldOutputRoutes()
		routes.keyPressed(13, route: .local)
		routes.keyPressed(14, route: .remote)
		routes.modifierPressedRemotely(mask: command)

		let taken = routes.takeRemoteHolds()
		XCTAssertEqual(taken.keys, [14])
		XCTAssertEqual(taken.modifierCounts, [command: 1])
		XCTAssertEqual(routes.keyReleased(13), .local)
		XCTAssertNil(routes.keyReleased(14))
		XCTAssertEqual(routes.remoteModifierCount(mask: command), 0)
	}
}
