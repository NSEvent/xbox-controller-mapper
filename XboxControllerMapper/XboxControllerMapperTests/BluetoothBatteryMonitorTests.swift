import XCTest
@testable import ControllerKeys

final class BluetoothBatteryMonitorTests: XCTestCase {

	func testSerialLikeNamesMatch() {
		// Siri Remote advertises its serial number as the Bluetooth name
		XCTAssertTrue(BluetoothBatteryMonitor.isSerialLikeName("c08qmz6m2330"))
		XCTAssertTrue(BluetoothBatteryMonitor.isSerialLikeName("gx9zwn9rjqh4"))
	}

	func testFriendlyDeviceNamesDoNotMatch() {
		// Names are compared lowercased by the monitor
		XCTAssertFalse(BluetoothBatteryMonitor.isSerialLikeName("magic keyboard"))
		XCTAssertFalse(BluetoothBatteryMonitor.isSerialLikeName("xbox wireless controller"))
		XCTAssertFalse(BluetoothBatteryMonitor.isSerialLikeName("kevin's airpods pro"))
		XCTAssertFalse(BluetoothBatteryMonitor.isSerialLikeName("dualsense"))  // no digit, also < 8 chars
		XCTAssertFalse(BluetoothBatteryMonitor.isSerialLikeName("keyboard"))   // 8 chars but no digit
	}

	func testLengthBounds() {
		XCTAssertFalse(BluetoothBatteryMonitor.isSerialLikeName("a1b2c3"))                       // too short
		XCTAssertFalse(BluetoothBatteryMonitor.isSerialLikeName("a1b2c3d4e5f6g7h8i9j0k"))        // too long (21)
		XCTAssertTrue(BluetoothBatteryMonitor.isSerialLikeName("a1b2c3d4"))                      // 8, minimum
		XCTAssertTrue(BluetoothBatteryMonitor.isSerialLikeName("a1b2c3d4e5f6g7h8i9j0"))          // 20, maximum
	}
}
