import XCTest
@testable import ControllerKeys

final class TrialExpiryNotificationPolicyTests: XCTestCase {
	func testLicensedNeverNotifies() {
		XCTAssertNil(event(for: .licensed))
		XCTAssertNil(event(for: .licensed, lastDayDelivered: true, expiredDelivered: true))
	}

	func testLastDayFiresOnlyAtOneDayRemaining() {
		XCTAssertEqual(event(for: .trial(daysRemaining: 1)), .lastDay)
		XCTAssertNil(event(for: .trial(daysRemaining: 2)))
		XCTAssertNil(event(for: .trial(daysRemaining: 14)))
	}

	func testExpiredFiresOnExpiry() {
		XCTAssertEqual(event(for: .expired), .expired)
		// The last-day marker doesn't suppress the expiry notification —
		// they're consecutive days of the same wind-down.
		XCTAssertEqual(event(for: .expired, lastDayDelivered: true), .expired)
	}

	func testEachEventFiresAtMostOnce() {
		XCTAssertNil(event(for: .trial(daysRemaining: 1), lastDayDelivered: true))
		XCTAssertNil(event(for: .expired, expiredDelivered: true))
	}

	func testNotificationIdentifiersAreDistinct() {
		let identifiers = TrialExpiryNotificationPolicy.Event.allCases.map(\.rawValue)
		XCTAssertEqual(Set(identifiers).count, identifiers.count)
	}

	private func event(
		for status: LicenseManager.Status,
		lastDayDelivered: Bool = false,
		expiredDelivered: Bool = false
	) -> TrialExpiryNotificationPolicy.Event? {
		TrialExpiryNotificationPolicy.event(
			for: status,
			lastDayDelivered: lastDayDelivered,
			expiredDelivered: expiredDelivered
		)
	}
}

@MainActor
final class LicenseUIRequestTests: XCTestCase {
	func testRequestStoresSurfaceOpensWindowAndPosts() {
		let center = NotificationCenter()
		var observed = false
		let observer = center.addObserver(
			forName: .openLicensePrompt, object: nil, queue: nil
		) { _ in observed = true }
		defer { center.removeObserver(observer) }

		var openedWindow = false
		LicenseUIRequest.request(surface: "menubar_expired", notificationCenter: center) {
			openedWindow = true
		}

		XCTAssertTrue(openedWindow)
		XCTAssertTrue(observed)
		XCTAssertEqual(LicenseUIRequest.consumePending(), "menubar_expired")
	}

	func testConsumePendingIsOneShot() {
		LicenseUIRequest.request(surface: "expiry_notification", notificationCenter: NotificationCenter()) {}
		XCTAssertEqual(LicenseUIRequest.consumePending(), "expiry_notification")
		XCTAssertNil(LicenseUIRequest.consumePending())
	}
}
