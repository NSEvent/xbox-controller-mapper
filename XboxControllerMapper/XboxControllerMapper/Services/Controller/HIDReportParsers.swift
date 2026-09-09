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

// MARK: - Wii Remote

/// Parses Nintendo Wii Remote (RVL-CNT-01 / -TR) HID input reports.
///
/// Layout verified by live capture on an original RVL-CNT-01 (2026-09-08).
/// Byte 0 is the report ID, included by the input callback:
///
///   Core buttons 0x30 (3 bytes): [0x30, BB1, BB2] — sent on change.
///   Data reports 0x31-0x37 also begin [id, BB1, BB2] with sensor payloads after.
///   Status 0x20 (7 bytes): [0x20, BB1, BB2, flags, 0, 0, battery] — battery
///     raw scale ≈ 0xC0 = full; flags bit 0x01 = battery low.
///
/// BB1: Left 0x01, Right 0x02, Down 0x04, Up 0x08, Plus 0x10.
/// BB2: Two 0x01, One 0x02, B 0x04, A 0x08, Minus 0x10, Home 0x80.
///
/// Distinct from NintendoHIDParser's report 0x30: the Pro Controller's is
/// ≥ 5 bytes with buttons at byte 4; the Wiimote's is exactly 3 bytes. The two
/// parsers are also never fed the same device (separate PID matchers).
struct WiimoteHIDParser: HIDReportParser {
    /// Full-charge reference per WiiBrew — raw 0xC0 ≈ fresh batteries.
    private static let batteryFullScale: Float = 0xC0

    func parse(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) -> HIDReportParseResult? {
        switch (reportID, length) {
        case (0x31, let len) where len >= 6:
            // Core buttons + accelerometer: [0x31, BB1, BB2, AX, AY, AZ].
            var result = HIDReportParseResult(wiimoteButtons: Self.buttons(report))
            result.wiimoteAccelX = Self.accelG(report[3])
            result.wiimoteAccelY = Self.accelG(report[4])
            result.wiimoteAccelZ = Self.accelG(report[5])
            return result
        case (0x33, let len) where len >= 18:
            // Buttons + accel + 12 bytes of extended-format IR:
            // [0x33, BB1, BB2, AX, AY, AZ, 4 × (Xlo, Ylo, hi/size)].
            var result = HIDReportParseResult(wiimoteButtons: Self.buttons(report))
            result.wiimoteAccelX = Self.accelG(report[3])
            result.wiimoteAccelY = Self.accelG(report[4])
            result.wiimoteAccelZ = Self.accelG(report[5])
            result.wiimoteIRPoints = Self.irPoints(report, offset: 6)
            return result
        case (0x30...0x37, let len) where len >= 3:
            return HIDReportParseResult(wiimoteButtons: Self.buttons(report))
        case (0x20, let len) where len >= 7:
            var result = HIDReportParseResult(wiimoteButtons: Self.buttons(report))
            result.wiimoteBatteryLevel = min(1.0, Float(report[6]) / Self.batteryFullScale)
            return result
        default:
            return nil
        }
    }

    private static func buttons(_ report: UnsafePointer<UInt8>) -> WiimoteButtons {
        WiimoteButtons(rawValue: UInt16(report[1]) | (UInt16(report[2]) << 8))
    }

    /// Raw accel byte → g units (zero point 0x80, ≈26 counts per g).
    private static func accelG(_ raw: UInt8) -> Float {
        (Float(raw) - 128.0) / 26.0
    }

    /// Extended IR format: per blob, byte0 = X<7:0>, byte1 = Y<7:0>,
    /// byte2 = Y<9:8><<6 | X<9:8><<4 | size. An unseen blob slot is 0xFF-filled.
    private static func irPoints(_ report: UnsafePointer<UInt8>, offset: Int) -> [WiimoteIRPoint] {
        var points: [WiimoteIRPoint] = []
        for i in 0..<4 {
            let b0 = report[offset + i * 3]
            let b1 = report[offset + i * 3 + 1]
            let b2 = report[offset + i * 3 + 2]
            if b0 == 0xFF && b1 == 0xFF && b2 == 0xFF { continue }
            points.append(WiimoteIRPoint(
                x: Int(b0) | ((Int(b2) & 0x30) << 4),
                y: Int(b1) | ((Int(b2) & 0xC0) << 2),
                size: Int(b2) & 0x0F
            ))
        }
        return points
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
