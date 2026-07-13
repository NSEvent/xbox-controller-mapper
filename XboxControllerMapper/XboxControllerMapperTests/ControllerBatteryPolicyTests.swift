import XCTest
import GameController
@testable import ControllerKeys

final class ControllerBatteryPolicyTests: XCTestCase {
	func testXboxWaitsForBluetoothBatteryInsteadOfTrustingInitialGameControllerZero() {
		let reading = ControllerBatteryReadingResolver.resolve(
			prefersBluetoothBattery: true,
			bluetoothLevel: nil,
			bluetoothIsCharging: false,
			controllerBatteryLevel: 0,
			controllerBatteryState: .unknown
		)

		XCTAssertNil(reading)
	}

	func testXboxUsesBluetoothBatteryWhenAvailable() {
		let reading = ControllerBatteryReadingResolver.resolve(
			prefersBluetoothBattery: true,
			bluetoothLevel: 82,
			bluetoothIsCharging: false,
			controllerBatteryLevel: 0,
			controllerBatteryState: .unknown
		)

		XCTAssertNotNil(reading)
		XCTAssertEqual(reading?.level ?? -1, 0.82, accuracy: 0.001)
		XCTAssertEqual(reading?.state, .discharging)
	}

	func testGameControllerBatteryFivePercentStepsArePreserved() {
		let reading = ControllerBatteryReadingResolver.resolve(
			prefersBluetoothBattery: false,
			bluetoothLevel: nil,
			bluetoothIsCharging: false,
			controllerBatteryLevel: 0.45,
			controllerBatteryState: .discharging
		)

		XCTAssertEqual(reading?.level ?? -1, 0.45, accuracy: 0.001)
	}

	func testXboxBluetoothBatteryIsClamped() {
		let reading = ControllerBatteryReadingResolver.resolve(
			prefersBluetoothBattery: true,
			bluetoothLevel: 125,
			bluetoothIsCharging: true,
			controllerBatteryLevel: nil,
			controllerBatteryState: nil
		)

		XCTAssertNotNil(reading)
		XCTAssertEqual(reading?.level ?? -1, 1.0, accuracy: 0.001)
		XCTAssertEqual(reading?.state, .charging)
	}

	func testNonXboxUsesKnownGameControllerBattery() {
		let reading = ControllerBatteryReadingResolver.resolve(
			prefersBluetoothBattery: false,
			bluetoothLevel: nil,
			bluetoothIsCharging: false,
			controllerBatteryLevel: 0.19,
			controllerBatteryState: .discharging
		)

		XCTAssertNotNil(reading)
		XCTAssertEqual(reading?.level ?? -1, 0.19, accuracy: 0.001)
		XCTAssertEqual(reading?.state, .discharging)
	}

	func testUnknownZeroBatteryIsNotDisplayableOrNotifiable() {
		XCTAssertFalse(
			ControllerBatteryDisplayPolicy.isKnown(level: 0, state: .unknown)
		)
		XCTAssertNil(
			ControllerBatteryDisplayPolicy.percentage(level: 0, state: .unknown)
		)
	}

	func testZeroDischargingBatteryIsKnownCritical() {
		XCTAssertTrue(
			ControllerBatteryDisplayPolicy.isKnown(level: 0, state: .discharging)
		)
		XCTAssertEqual(
			ControllerBatteryDisplayPolicy.percentage(level: 0, state: .discharging),
			0
		)
	}
}
