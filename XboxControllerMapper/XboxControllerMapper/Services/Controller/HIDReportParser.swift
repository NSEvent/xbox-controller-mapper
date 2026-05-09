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
