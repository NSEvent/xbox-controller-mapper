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

/// Parses Nintendo Pro Controller HID input reports for the Home button, and
/// (for the simple 0x3F report) the left-stick axes.
///
/// Report layout (byte 0 is the report ID, included by the input callback):
///   Standard report 0x30: buttons2 at byte 4; LEFT stick 12-bit packed at
///                         bytes 6..8 (b6=Xlo, b7 lo nibble=Xhi, b7 hi nibble=
///                         Ylo, b8=Yhi), neutral 0x7FF.
///   Simple   report 0x3F: buttons2 at byte 2 (Home in buttons_hi);
///                         hat at byte 3; four 16-bit LE axes at bytes 4..11
///                         (a0=X, a1=Y, a2=Rx, a3=Ry), neutral 0x7FFF.
///
/// buttons2 bit layout: bit 4 (0x10) = Home.
///
/// On stickless 8BitDo clones the d-pad is funneled through the left stick.
/// Different clones use different reports — the Zero 2 sends 0x3F (16-bit
/// axes), the Micro sends 0x30 (12-bit packed) — so we extract the left stick
/// from both. Output convention: +x right, +y up.
struct NintendoHIDParser: HIDReportParser {
    /// Empirically verified on 8BitDo Zero 2 / Micro (Switch mode): X max =
    /// right / min = left; Y max = down / min = up. Standard HID convention.
    private static let axis16Center = 0x7FFF
    private static let axis16Range = Double(0xFFFF)
    private static let axis12Center = 0x7FF
    private static let axis12Range = Double(0xFFF)

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

        var result = HIDReportParseResult(
            nintendoHome: (report[buttons2Offset] & 0x10) != 0
        )

        if reportID == 0x3F, length >= 8 {
            // Simple report: 16-bit LE left-stick axes at bytes 4..7. These
            // follow standard HID (Y increases downward → up is the low value).
            let a0 = Int(report[4]) | (Int(report[5]) << 8)
            let a1 = Int(report[6]) | (Int(report[7]) << 8)
            setLeftStick(&result, x: a0, y: a1, center: Self.axis16Center, range: Self.axis16Range, yUpIsHigh: false)
        } else if reportID == 0x30, length >= 9 {
            // Standard report: 12-bit packed left stick at bytes 6..8. This
            // uses Nintendo's proprietary stick encoding where Y is INVERTED
            // vs HID — up is the HIGH value (verified on an 8BitDo Micro).
            let b6 = Int(report[6]); let b7 = Int(report[7]); let b8 = Int(report[8])
            let x12 = b6 | ((b7 & 0x0F) << 8)
            let y12 = (b7 >> 4) | (b8 << 4)
            setLeftStick(&result, x: x12, y: y12, center: Self.axis12Center, range: Self.axis12Range, yUpIsHigh: true)
        }

        return result
    }

    /// +x = right (raw high). +y = up. `yUpIsHigh` picks the Y convention:
    /// false = standard HID (up is the low value), true = Nintendo 0x30
    /// (up is the high value).
    private func setLeftStick(_ result: inout HIDReportParseResult, x: Int, y: Int, center: Int, range: Double, yUpIsHigh: Bool) {
        let nx = Double(x - center) / (range / 2.0)
        let ny = Double(yUpIsHigh ? (y - center) : (center - y)) / (range / 2.0)
        result.leftStickX = Float(max(-1.0, min(1.0, nx)))
        result.leftStickY = Float(max(-1.0, min(1.0, ny)))
    }
}
