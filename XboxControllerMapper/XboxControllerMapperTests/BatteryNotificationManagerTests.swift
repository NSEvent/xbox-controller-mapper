import XCTest
import GameController
@testable import ControllerKeys

final class BatteryNotificationManagerTests: XCTestCase {
	func testRepeatedFifteenPercentUpdatesNotifyOnlyOnce() {
		var policy = BatteryNotificationPolicy()
		let controller = makeIdentity("dualshock-4")

		XCTAssertEqual(policy.update(level: 0.15, identity: controller), 15)
		XCTAssertNil(policy.update(level: 0.15, identity: controller))
		XCTAssertNil(policy.update(level: 0.15, identity: controller))
	}

	func testSameControllerReconnectAtFifteenPercentDoesNotRearmNotification() {
		var policy = BatteryNotificationPolicy()
		let controller = makeIdentity("dualshock-4")

		XCTAssertEqual(policy.update(level: 0.15, identity: controller), 15)
		XCTAssertNil(policy.update(level: -1, isConnected: false, identity: nil))
		XCTAssertNil(policy.update(level: 0.15, identity: controller))
	}

	func testEachDescendingThresholdNotifiesOnce() {
		var policy = BatteryNotificationPolicy()
		let controller = makeIdentity("dualshock-4")

		XCTAssertEqual(policy.update(level: 0.20, identity: controller), 20)
		XCTAssertNil(policy.update(level: 0.20, identity: controller))
		XCTAssertEqual(policy.update(level: 0.15, identity: controller), 15)
		XCTAssertEqual(policy.update(level: 0.10, identity: controller), 10)
		XCTAssertEqual(policy.update(level: 0.05, identity: controller), 5)
		XCTAssertNil(policy.update(level: 0.05, identity: controller))
	}

	func testStartingAtFifteenPercentDoesNotBackfillTwentyPercent() {
		var policy = BatteryNotificationPolicy()
		let controller = makeIdentity("dualshock-4")

		XCTAssertEqual(policy.update(level: 0.15, identity: controller), 15)
		XCTAssertNil(policy.update(level: 0.20, identity: controller))
		XCTAssertEqual(policy.update(level: 0.10, identity: controller), 10)
	}

	func testRechargeAboveTwentyFivePercentStartsNewDischargeCycle() {
		var policy = BatteryNotificationPolicy()
		let controller = makeIdentity("dualshock-4")

		XCTAssertEqual(policy.update(level: 0.15, identity: controller), 15)
		XCTAssertNil(policy.update(level: 0.26, identity: controller))
		XCTAssertEqual(policy.update(level: 0.20, identity: controller), 20)
	}

	func testDifferentControllerStartsIndependentDischargeCycle() {
		var policy = BatteryNotificationPolicy()

		XCTAssertEqual(policy.update(level: 0.15, identity: makeIdentity("controller-a")), 15)
		XCTAssertEqual(policy.update(level: 0.15, identity: makeIdentity("controller-b")), 15)
	}

	func testUnknownBatteryReadingDoesNotNotify() {
		var policy = BatteryNotificationPolicy()

		XCTAssertNil(
			policy.thresholdToNotify(
				level: 0,
				state: .unknown,
				isConnected: true,
				identity: makeIdentity("dualshock-4")
			)
		)
	}

	private func makeIdentity(_ id: String) -> ControllerIdentity {
		ControllerIdentity(
			stableId: id,
			fallbackId: id,
			vendorId: nil,
			productId: nil,
			productName: nil,
			transport: nil,
			serialNumber: nil,
			deviceAddress: nil
		)
	}
}

private extension BatteryNotificationPolicy {
	mutating func update(
		level: Float,
		isConnected: Bool = true,
		identity: ControllerIdentity?
	) -> Int? {
		thresholdToNotify(
			level: level,
			state: .discharging,
			isConnected: isConnected,
			identity: identity
		)
	}
}
