import Foundation

// MARK: - DualSense

/// Parses DualSense / DualSense Edge HID input reports.
///
/// USB report 0x01: buttons3 at byte 10, battery status at byte 53.
/// BT  report 0x31: buttons3 at byte 11, battery status at byte 54.
///
/// buttons3 bit layout (shared across USB/BT):
///   bit 0 PS, bit 1 Touchpad, bit 2 Mic mute,
///   bit 4 Left fn (Edge), bit 5 Right fn (Edge),
///   bit 6 Left paddle (Edge), bit 7 Right paddle (Edge).
///
/// Battery byte: bits 7:4 = power state (0x1 = charging).
struct DualSenseHIDParser: HIDReportParser {
    func parse(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) -> HIDReportParseResult? {
        let buttons3Offset: Int
        let batteryOffset: Int
        switch (reportID, length) {
        case (0x01, let len) where len >= 11:
            buttons3Offset = 10
            batteryOffset = 53
        case (0x31, let len) where len >= 12:
            buttons3Offset = 11
            batteryOffset = 54
        default:
            return nil
        }

        guard buttons3Offset < length else { return nil }

        let b3 = report[buttons3Offset]
        var result = HIDReportParseResult(
            ps: (b3 & 0x01) != 0,
            mic: (b3 & 0x04) != 0,
            edgeLeftFunction: (b3 & 0x10) != 0,
            edgeRightFunction: (b3 & 0x20) != 0,
            edgeLeftPaddle: (b3 & 0x40) != 0,
            edgeRightPaddle: (b3 & 0x80) != 0
        )

        if batteryOffset < length {
            let powerState = (report[batteryOffset] >> 4) & 0x0F
            result.batteryCharging = (powerState == 0x01)
        }

        return result
    }
}

// MARK: - DualShock 4

/// Parses DualShock 4 (v1 and v2) HID input reports.
///
/// USB report 0x01: buttons3 at byte 7, battery status at byte 30.
/// BT  report 0x11: buttons3 at byte 9, battery status at byte 32.
///
/// buttons3 bit layout: bit 0 PS, bit 1 Touchpad. (No mic, no Edge buttons.)
/// Battery byte: bit 4 = cable state (1 = charging / plugged in).
struct DualShockHIDParser: HIDReportParser {
    func parse(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) -> HIDReportParseResult? {
        let buttons3Offset: Int
        let batteryOffset: Int
        switch (reportID, length) {
        case (0x01, let len) where len >= 8:
            buttons3Offset = 7
            batteryOffset = 30
        case (0x11, let len) where len >= 10:
            buttons3Offset = 9
            batteryOffset = 32
        default:
            return nil
        }

        guard buttons3Offset < length else { return nil }

        let b3 = report[buttons3Offset]
        var result = HIDReportParseResult(
            ps: (b3 & 0x01) != 0
        )

        if batteryOffset < length {
            result.batteryCharging = (report[batteryOffset] & 0x10) != 0
        }

        return result
    }
}

// MARK: - Nintendo Pro Controller

/// Parses Nintendo Pro Controller HID input reports for the Home button.
///
/// Standard report 0x30: buttons2 at byte 4.
/// Simple   report 0x3F: buttons2 at byte 2 (Home in buttons_hi).
///
/// buttons2 bit layout: bit 4 (0x10) = Home.
struct NintendoHIDParser: HIDReportParser {
    func parse(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) -> HIDReportParseResult? {
        let buttons2Offset: Int
        switch (reportID, length) {
        case (0x30, let len) where len >= 5:
            buttons2Offset = 4
        case (0x3F, let len) where len >= 3:
            buttons2Offset = 2
        default:
            return nil
        }

        guard buttons2Offset < length else { return nil }

        return HIDReportParseResult(
            nintendoHome: (report[buttons2Offset] & 0x10) != 0
        )
    }
}
