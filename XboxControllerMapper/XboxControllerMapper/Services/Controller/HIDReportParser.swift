import Foundation

/// Pure result of parsing one HID input report from a controller.
/// Each parser fills only the fields its controller can extract — `nil` means
/// "this report type doesn't carry this signal."
///
/// Kept flat (rather than per-controller variants) so the handler doesn't need
/// to switch on the parser type to read the buttons.
struct HIDReportParseResult: Equatable {
    var ps: Bool? = nil
    var mic: Bool? = nil
    var edgeLeftFunction: Bool? = nil
    var edgeRightFunction: Bool? = nil
    var edgeLeftPaddle: Bool? = nil
    var edgeRightPaddle: Bool? = nil
    var nintendoHome: Bool? = nil
    /// True = charging, false = not. Nil when the report type doesn't expose it.
    var batteryCharging: Bool? = nil
	/// Hardware finger count; unlike GameController axes, idle coordinates
	/// cannot masquerade as a contact. Nil for reports without touch data.
	var touchpadContactCount: Int? = nil
    /// Left-stick axes from the Nintendo simple (0x3F) report, normalized to
    /// -1...1 with +x = right and +y = up (GameController convention). On
    /// stickless 8BitDo clones these carry the d-pad; nil when unavailable.
    var leftStickX: Float? = nil
    var leftStickY: Float? = nil
    /// Wii Remote core-button state (all eleven buttons as one mask so the
    /// handler can diff old^new in a single operation). Nil for non-Wiimote
    /// reports.
    var wiimoteButtons: WiimoteButtons? = nil
    /// Wii Remote battery level 0...1 from the 0x20 status report.
    var wiimoteBatteryLevel: Float? = nil
    /// Wii Remote accelerometer in g units from the 0x31/0x33 reports (zero
    /// point 0x80, ≈26 counts per g). Nil when the report carries no accel.
    var wiimoteAccelX: Float? = nil
    var wiimoteAccelY: Float? = nil
    var wiimoteAccelZ: Float? = nil
    /// Tracked IR camera blobs from the 0x33 report (camera field 1024×768).
    /// Nil when the report carries no IR data; empty when no blobs are seen.
    var wiimoteIRPoints: [WiimoteIRPoint]? = nil
}

/// One tracked IR blob from the Wii Remote camera.
struct WiimoteIRPoint: Equatable, Sendable {
    let x: Int      // 0...1023
    let y: Int      // 0...767
    let size: Int   // 0...15
}

/// Wii Remote core-button bitmask: low byte = the report's first button byte,
/// high byte = the second (raw = UInt16(bb1) | UInt16(bb2) << 8).
struct WiimoteButtons: OptionSet, Equatable, Sendable {
    let rawValue: UInt16

    static let dpadLeft  = WiimoteButtons(rawValue: 0x0001)
    static let dpadRight = WiimoteButtons(rawValue: 0x0002)
    static let dpadDown  = WiimoteButtons(rawValue: 0x0004)
    static let dpadUp    = WiimoteButtons(rawValue: 0x0008)
    static let plus      = WiimoteButtons(rawValue: 0x0010)
    static let two       = WiimoteButtons(rawValue: 0x0100)
    static let one       = WiimoteButtons(rawValue: 0x0200)
    static let b         = WiimoteButtons(rawValue: 0x0400)
    static let a         = WiimoteButtons(rawValue: 0x0800)
    static let minus     = WiimoteButtons(rawValue: 0x1000)
    static let home      = WiimoteButtons(rawValue: 0x8000)
}

/// One parser per controller family. Owns its (reportID, length, offset,
/// bitmask) knowledge so the handler stays a thin dispatch + state-diff layer.
///
/// Parsers are stateless — state diffing and event dispatch happen on the
/// caller side, against `storage.last*` fields.
protocol HIDReportParser {
    /// Parse one HID input report. Returns nil if the (reportID, length)
    /// combination isn't recognized by this parser.
    func parse(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) -> HIDReportParseResult?
}
