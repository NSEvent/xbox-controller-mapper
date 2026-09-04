import XCTest
@testable import ControllerKeys

@MainActor
final class SettingsUIRequestTests: XCTestCase {
	override func setUp() {
		super.setUp()
		SettingsUIRequest.consumePending()
	}

	override func tearDown() {
		SettingsUIRequest.consumePending()
		super.tearDown()
	}

	func testRequestOpensWindowBeforePostingAndRemainsPendingUntilConsumed() {
		let notificationCenter = NotificationCenter()
		var events: [String] = []
		let observer = notificationCenter.addObserver(
			forName: .openSettingsSheet,
			object: nil,
			queue: nil
		) { _ in
			events.append("notification")
		}
		defer { notificationCenter.removeObserver(observer) }

		SettingsUIRequest.request(notificationCenter: notificationCenter) {
			XCTAssertTrue(SettingsUIRequest.pending)
			events.append("open-window")
		}

		XCTAssertEqual(events, ["open-window", "notification"])
		XCTAssertTrue(SettingsUIRequest.consumePending())
		XCTAssertFalse(SettingsUIRequest.consumePending())
	}
}
