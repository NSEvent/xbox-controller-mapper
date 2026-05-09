import XCTest
@testable import ControllerKeys

/// Hand-crafted byte buffer tests for HID report parsers. Previously, this
/// logic was only exercised by plugging in a physical controller — these tests
/// pin the (reportID, length, offset, bitmask) tables to behavior so future
/// edits can't silently regress them.
final class HIDReportParserTests: XCTestCase {

    // MARK: - Helpers

    private func makeReport(length: Int, configure: (UnsafeMutablePointer<UInt8>) -> Void) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: length)
        bytes.withUnsafeMutableBufferPointer { buf in
            configure(buf.baseAddress!)
        }
        return bytes
    }

    private func parse(_ parser: HIDReportParser, reportID: UInt32, bytes: [UInt8]) -> HIDReportParseResult? {
        bytes.withUnsafeBufferPointer { buf in
            parser.parse(reportID: reportID, report: buf.baseAddress!, length: buf.count)
        }
    }

    // MARK: - DualSense

    func testDualSense_USBReport_extractsAllButtonsFromButtons3() {
        let bytes = makeReport(length: 60) { p in
            // buttons3 at offset 10, all bits set
            p[10] = 0xF7  // PS, mic, edge fns + paddles, NOT touchpad (bit 1)
        }
        let result = parse(DualSenseHIDParser(), reportID: 0x01, bytes: bytes)

        XCTAssertEqual(result?.ps, true)
        XCTAssertEqual(result?.mic, true)
        XCTAssertEqual(result?.edgeLeftFunction, true)
        XCTAssertEqual(result?.edgeRightFunction, true)
        XCTAssertEqual(result?.edgeLeftPaddle, true)
        XCTAssertEqual(result?.edgeRightPaddle, true)
    }

    func testDualSense_BTReport_usesOffset11NotOffset10() {
        let bytes = makeReport(length: 60) { p in
            // Set mismatched bytes at the two candidate offsets to confirm
            // the parser picks the BT offset.
            p[10] = 0x01  // would be PS if parser mistakenly used USB offset
            p[11] = 0x04  // mic only at the correct BT offset
        }
        let result = parse(DualSenseHIDParser(), reportID: 0x31, bytes: bytes)

        XCTAssertEqual(result?.ps, false, "Parser must read offset 11 for BT, not offset 10")
        XCTAssertEqual(result?.mic, true)
    }

    func testDualSense_USBBattery_chargingDetectedFromPowerStateNibble() {
        let bytes = makeReport(length: 60) { p in
            p[10] = 0x00
            // Power state 0x1 in the upper nibble = charging
            p[53] = 0x10
        }
        let result = parse(DualSenseHIDParser(), reportID: 0x01, bytes: bytes)
        XCTAssertEqual(result?.batteryCharging, true)
    }

    func testDualSense_USBBattery_completeStateIsNotCharging() {
        let bytes = makeReport(length: 60) { p in
            // Power state 0x2 = charge complete (different from "currently charging")
            p[53] = 0x20
        }
        let result = parse(DualSenseHIDParser(), reportID: 0x01, bytes: bytes)
        XCTAssertEqual(result?.batteryCharging, false)
    }

    func testDualSense_TooShortReport_returnsNil() {
        let bytes = makeReport(length: 5) { _ in }
        XCTAssertNil(parse(DualSenseHIDParser(), reportID: 0x01, bytes: bytes))
    }

    func testDualSense_UnknownReportID_returnsNil() {
        let bytes = makeReport(length: 60) { _ in }
        XCTAssertNil(parse(DualSenseHIDParser(), reportID: 0xFF, bytes: bytes))
    }

    // MARK: - DualShock 4

    func testDualShock_USBReport_psFromOffset7_noMicNoEdge() {
        let bytes = makeReport(length: 35) { p in
            p[7] = 0xFF  // every bit on
        }
        let result = parse(DualShockHIDParser(), reportID: 0x01, bytes: bytes)

        XCTAssertEqual(result?.ps, true)
        // DS4 doesn't have these buttons — parser must leave them nil so the
        // handler's diff/dispatch step skips them.
        XCTAssertNil(result?.mic)
        XCTAssertNil(result?.edgeLeftFunction)
        XCTAssertNil(result?.edgeRightPaddle)
    }

    func testDualShock_BTReport_psFromOffset9() {
        let bytes = makeReport(length: 35) { p in
            p[7] = 0x01  // would be PS if BT mistakenly used USB offset
            p[9] = 0x00
        }
        let result = parse(DualShockHIDParser(), reportID: 0x11, bytes: bytes)
        XCTAssertEqual(result?.ps, false, "BT must read offset 9, not offset 7")
    }

    func testDualShock_USBBattery_cableStateBit4MeansCharging() {
        let bytes = makeReport(length: 35) { p in
            p[30] = 0x10  // cable state bit
        }
        let result = parse(DualShockHIDParser(), reportID: 0x01, bytes: bytes)
        XCTAssertEqual(result?.batteryCharging, true)
    }

    // MARK: - Nintendo

    func testNintendo_StandardReport_homeFromOffset4Bit4() {
        let bytes = makeReport(length: 6) { p in
            p[4] = 0x10  // Home bit
        }
        let result = parse(NintendoHIDParser(), reportID: 0x30, bytes: bytes)
        XCTAssertEqual(result?.nintendoHome, true)
    }

    func testNintendo_SimpleReport_homeFromOffset2Bit4() {
        // Length 5 (not 4) so byte index 4 exists — the trap value at offset 4
        // makes the test catch a regression where the parser confuses the
        // simple-report offset (2) with the standard-report offset (4). With
        // length: 4 the parser's `buttons2Offset < length` guard would mask
        // such a bug AND writing `p[4]` would be out of bounds.
        let bytes = makeReport(length: 5) { p in
            p[4] = 0x10  // would be Home if simple report mistakenly used standard offset
            p[2] = 0x00
        }
        let result = parse(NintendoHIDParser(), reportID: 0x3F, bytes: bytes)
        XCTAssertEqual(result?.nintendoHome, false)
    }

    func testNintendo_OtherButtonsInSameByte_dontTriggerHome() {
        let bytes = makeReport(length: 6) { p in
            p[4] = 0xEF  // every bit except 0x10
        }
        let result = parse(NintendoHIDParser(), reportID: 0x30, bytes: bytes)
        XCTAssertEqual(result?.nintendoHome, false)
    }
}
