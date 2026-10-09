import XCTest
@testable import ControllerKeys

/// Pins complete numbered reports, including the ID IOHIDDeviceSetReport needs
/// in the buffer. Hardware background behavior remains a separate acceptance test.
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
        s.playerLEDs = PlayerLEDs()
        return s
    }

    private func storedCRC(_ report: [UInt8]) -> UInt32 {
        UInt32(report[74]) | (UInt32(report[75]) << 8) | (UInt32(report[76]) << 16) | (UInt32(report[77]) << 24)
    }

    // MARK: CRC32

    func testCRC32MatchesKnownVector() {
        // Standard CRC-32 check value for "123456789"
        XCTAssertEqual(PlayStationLEDReports.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    // MARK: DualShock 4 (report ID 0x11)

    func testDualShock4PayloadLayout() {
        let report = PlayStationLEDReports.dualShock4Bluetooth(settings: settings())

        XCTAssertEqual(report.count, 78)
        XCTAssertEqual(report[0], 0x11, "IOKit does not prepend the numbered report ID")
        XCTAssertEqual(report[1], 0xC0, "hw_control: HID | CRC32 enable")
        XCTAssertEqual(report[3], 0x07, "MOTOR | LED | BLINK, matching ds4color")
        XCTAssertEqual(report[6], 0, "LED report must not rumble")
        XCTAssertEqual(report[7], 0, "LED report must not rumble")
        XCTAssertEqual(Array(report[8...10]), [255, 0, 0])
        XCTAssertEqual(Array(report[11...12]), [0, 0], "Clear previous flash durations")
    }

    func testDualShock4BrightnessScalesRGB() {
        let report = PlayStationLEDReports.dualShock4Bluetooth(settings: settings(brightness: .mid))
        XCTAssertEqual(Array(report[8...10]), [128, 0, 0])
    }

    func testDualShock4DisabledLightBarZeroesRGB() {
        let report = PlayStationLEDReports.dualShock4Bluetooth(settings: settings(enabled: false))
        XCTAssertEqual(Array(report[8...10]), [0, 0, 0])
    }

    func testDualShock4CRCTrailerCoversSeedReportIDAndBody() {
        let report = PlayStationLEDReports.dualShock4Bluetooth(settings: settings())
        let expected = PlayStationLEDReports.crc32(
            Data([0xA2] + report[0..<74])
        )
        XCTAssertEqual(storedCRC(report), expected)
    }

    // MARK: DualSense (report ID 0x31)

    func testDualSensePayloadLayout() {
        let report = PlayStationLEDReports.dualSenseBluetooth(settings: settings(), sequence: 5)

        XCTAssertEqual(report.count, 78)
        XCTAssertEqual(report[0], 0x31, "IOKit does not prepend the numbered report ID")
        XCTAssertEqual(report[1], 0x50, "upper nibble carries the sequence number")
        XCTAssertEqual(report[2], 0x10, "DS_OUTPUT_TAG")
        XCTAssertEqual(report[3], 0xFF, "valid flag0: enable all")
        XCTAssertEqual(report[4], 0x57, "valid flag1")
        XCTAssertEqual(report[3 + DualSenseHIDConstants.lightbarRedOffset], 255)
        XCTAssertEqual(report[3 + DualSenseHIDConstants.lightbarGreenOffset], 0)
        XCTAssertEqual(report[3 + DualSenseHIDConstants.lightbarBlueOffset], 0)
    }

    func testDualSenseSequenceZeroEncodesAsZeroHeader() {
        let report = PlayStationLEDReports.dualSenseBluetooth(settings: settings(), sequence: 0)
        XCTAssertEqual(report[1], 0x00)
    }

    func testDualSenseCRCTrailerCoversSeedReportIDAndBody() {
        let report = PlayStationLEDReports.dualSenseBluetooth(settings: settings(), sequence: 0)
        let expected = PlayStationLEDReports.crc32(
            Data([0xA2] + report[0..<74])
        )
        XCTAssertEqual(storedCRC(report), expected)
    }

    func testDS4MatchesIndependentDs4colorRedFixture() {
        // ds4color/core.py _bt_report(255, 0, 0), a6e491de82e7969eda1d0341583a31cb3b01ea1a.
        // CRC calculated with Python zlib, not our production CRC implementation.
        let expected: [UInt8] = [0x11, 0xC0, 0, 7, 0, 0, 0, 0, 255]
            + Array(repeating: 0, count: 65) + [0x69, 0x6C, 0x2B, 0x16]
        XCTAssertEqual(PlayStationLEDReports.dualShock4Bluetooth(settings: settings()), expected)
    }

    func testDualSenseMatchesIndependentFullReportFixture() {
        // Complete 0x31 report: sequence 5, red, player/mute LEDs off, bright.
        // Fixed trailer computed independently using Python zlib.crc32.
        let expected: [UInt8] = [0x31, 0x50, 0x10, 0xFF, 0x57]
            + Array(repeating: 0, count: 36) + [3]
            + Array(repeating: 0, count: 5) + [255]
            + Array(repeating: 0, count: 26) + [0xE7, 0x3C, 0xCF, 0xDF]
        XCTAssertEqual(PlayStationLEDReports.dualSenseBluetooth(settings: settings(), sequence: 5), expected)
    }
}
