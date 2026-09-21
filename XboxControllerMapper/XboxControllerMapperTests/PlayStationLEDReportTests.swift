import XCTest
@testable import ControllerKeys

/// Pins the raw Bluetooth LED report layouts (per Linux hid-playstation.c).
/// These payloads became load-bearing on macOS 27, where GCDeviceLight is
/// foreground-scoped and reverts the light bar for backgrounded apps — and
/// no controller hardware exists on CI, so the exact bytes are verified here.
final class PlayStationLEDReportTests: XCTestCase {

    private func settings(
        red: Double = 1.0, green: Double = 0.0, blue: Double = 0.0,
        brightness: LightBarBrightness = .bright,
        enabled: Bool = true
    ) -> DualSenseLEDSettings {
        var s = DualSenseLEDSettings()
        s.lightBarColor = CodableColor(red: red, green: green, blue: blue)
        s.lightBarBrightness = brightness
        s.lightBarEnabled = enabled
        return s
    }

    private func storedCRC(_ report: [UInt8]) -> UInt32 {
        UInt32(report[73]) | (UInt32(report[74]) << 8) | (UInt32(report[75]) << 16) | (UInt32(report[76]) << 24)
    }

    // MARK: CRC32

    func testCRC32MatchesKnownVector() {
        // Standard CRC-32 check value for "123456789"
        XCTAssertEqual(PlayStationLEDReports.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    // MARK: DualShock 4 (report ID 0x11)

    func testDualShock4PayloadLayout() {
        let report = PlayStationLEDReports.dualShock4Bluetooth(settings: settings())

        XCTAssertEqual(report.count, DualShock4HIDConstants.btReportSize - 1)
        XCTAssertEqual(report[0], 0xC0, "hw_control: HID | CRC32 enable")
        XCTAssertEqual(report[2], 0x03, "valid_flag0 must set MOTOR | LED for DS4 firmware")
        XCTAssertEqual(report[5], 0, "LED report must not rumble")
        XCTAssertEqual(report[6], 0, "LED report must not rumble")
        XCTAssertEqual(Array(report[7...9]), [255, 0, 0])
    }

    func testDualShock4BrightnessScalesRGB() {
        let report = PlayStationLEDReports.dualShock4Bluetooth(settings: settings(brightness: .mid))
        XCTAssertEqual(Array(report[7...9]), [128, 0, 0])
    }

    func testDualShock4DisabledLightBarZeroesRGB() {
        let report = PlayStationLEDReports.dualShock4Bluetooth(settings: settings(enabled: false))
        XCTAssertEqual(Array(report[7...9]), [0, 0, 0])
    }

    func testDualShock4CRCTrailerCoversSeedReportIDAndBody() {
        let report = PlayStationLEDReports.dualShock4Bluetooth(settings: settings())
        let expected = PlayStationLEDReports.crc32(
            Data([0xA2, DualShock4HIDConstants.btOutputReportID] + report[0..<73])
        )
        XCTAssertEqual(storedCRC(report), expected)
    }

    // MARK: DualSense (report ID 0x31)

    func testDualSensePayloadLayout() {
        let report = PlayStationLEDReports.dualSenseBluetooth(settings: settings(), sequence: 5)

        XCTAssertEqual(report.count, DualSenseHIDConstants.bluetoothReportSize - 1)
        XCTAssertEqual(report[0], 0x50, "upper nibble carries the sequence number")
        XCTAssertEqual(report[1], 0x10, "DS_OUTPUT_TAG")
        XCTAssertEqual(report[2], 0xFF, "valid flag0: enable all")
        XCTAssertEqual(report[3], 0x57, "valid flag1")
        XCTAssertEqual(report[2 + DualSenseHIDConstants.lightbarRedOffset], 255)
        XCTAssertEqual(report[2 + DualSenseHIDConstants.lightbarGreenOffset], 0)
        XCTAssertEqual(report[2 + DualSenseHIDConstants.lightbarBlueOffset], 0)
    }

    func testDualSenseSequenceZeroEncodesAsZeroHeader() {
        let report = PlayStationLEDReports.dualSenseBluetooth(settings: settings(), sequence: 0)
        XCTAssertEqual(report[0], 0x00)
    }

    func testDualSenseCRCTrailerCoversSeedReportIDAndBody() {
        let report = PlayStationLEDReports.dualSenseBluetooth(settings: settings(), sequence: 0)
        let expected = PlayStationLEDReports.crc32(
            Data([0xA2, DualSenseHIDConstants.bluetoothOutputReportID] + report[0..<73])
        )
        XCTAssertEqual(storedCRC(report), expected)
    }
}
