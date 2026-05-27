import XCTest
import GameController
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

    // MARK: - Steam Controller

    func testSteamController_Report45ParsesButtonsAndAxes() {
        let bytes = makeReport(length: 29) { p in
            p[0] = 7  // sequence
            writeLE32(SteamControllerButtonMask.a | SteamControllerButtonMask.steam | SteamControllerButtonMask.leftUpperGrip, to: p, offset: 1)
            writeLE16(0x4000, to: p, offset: 5)       // left trigger = 0.5
            writeLE16(0x7FFF, to: p, offset: 7)       // right trigger = 1.0
            writeLE16(0x7FFF, to: p, offset: 9)       // left stick x = 1.0
            writeLE16(UInt16(bitPattern: Int16(-32768)), to: p, offset: 11)
            writeLE16(UInt16(bitPattern: Int16(-16384)), to: p, offset: 13)
            writeLE16(0x4000, to: p, offset: 15)
        }

        let result = bytes.withUnsafeBufferPointer { buf in
            SteamControllerHIDParser().parse(reportID: 0x45, report: buf.baseAddress!, length: buf.count)
        }

        XCTAssertEqual(result?.reportID, 0x45)
        XCTAssertEqual(result?.sequence, 7)
        XCTAssertEqual(result?.buttons, SteamControllerButtonMask.a | SteamControllerButtonMask.steam | SteamControllerButtonMask.leftUpperGrip)
        XCTAssertEqual(result?.leftTrigger ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(result?.rightTrigger ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(result?.leftStickX ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(result?.leftStickY ?? 0, -1.0, accuracy: 0.001)
        XCTAssertEqual(result?.rightStickX ?? 0, -0.5, accuracy: 0.001)
        XCTAssertEqual(result?.rightStickY ?? 0, 0.5, accuracy: 0.001)
    }

    func testSteamController_ReportWithLeadingIDByteIsAccepted() {
        let bytes = makeReport(length: 30) { p in
            p[0] = 0x45
            p[1] = 9
            writeLE32(SteamControllerButtonMask.menu, to: p, offset: 2)
        }

        let result = bytes.withUnsafeBufferPointer { buf in
            SteamControllerHIDParser().parse(reportID: 0x45, report: buf.baseAddress!, length: buf.count)
        }

        XCTAssertEqual(result?.sequence, 9)
        XCTAssertEqual(result?.buttons, SteamControllerButtonMask.menu)
    }

    func testSteamController_BatteryReportParsesLevelAndDischargingState() {
        let bytes = makeReport(length: 14) { p in
            p[0] = 1   // discharging
            p[1] = 87  // 87%
        }

        let result = bytes.withUnsafeBufferPointer { buf in
            SteamControllerHIDParser().parseBattery(reportID: 0x43, report: buf.baseAddress!, length: buf.count)
        }

        XCTAssertEqual(result?.reportID, 0x43)
        XCTAssertEqual(result?.chargeState, 1)
        XCTAssertEqual(result?.level ?? -1, 0.87, accuracy: 0.001)
        XCTAssertEqual(result?.state, .discharging)
    }

    func testSteamController_BatteryReportWithLeadingIDByteParsesChargingState() {
        let bytes = makeReport(length: 15) { p in
            p[0] = 0x43
            p[1] = 2
            p[2] = 100
        }

        let result = bytes.withUnsafeBufferPointer { buf in
            SteamControllerHIDParser().parseBattery(reportID: 0x43, report: buf.baseAddress!, length: buf.count)
        }

        XCTAssertEqual(result?.level ?? -1, 1.0, accuracy: 0.001)
        XCTAssertEqual(result?.state, .charging)
    }

    func testSteamController_MacOSCallbackReportUsesDecimalReportIDAndLeadingIDByte() {
        let bytes = makeReport(length: 46) { p in
            p[0] = 0x45
            p[1] = 11
            writeLE32(SteamControllerButtonMask.a | SteamControllerButtonMask.rightBumper, to: p, offset: 2)
        }

        let result = bytes.withUnsafeBufferPointer { buf in
            SteamControllerHIDParser().parse(reportID: 69, report: buf.baseAddress!, length: buf.count)
        }

        XCTAssertEqual(result?.reportID, 0x45)
        XCTAssertEqual(result?.sequence, 11)
        XCTAssertEqual(result?.buttons, SteamControllerButtonMask.a | SteamControllerButtonMask.rightBumper)
    }

    func testSteamController_AcceptsObservedMacOSVendorUsages() {
        XCTAssertTrue(SteamControllerHIDParser.acceptedVendorUsages.contains(SteamControllerHIDParser.vendorDataUsage))
        XCTAssertTrue(SteamControllerHIDParser.acceptedVendorUsages.contains(SteamControllerHIDParser.vendorCommandUsage))
    }

    func testSteamController_UnknownReportIDReturnsNil() {
        let bytes = makeReport(length: 29) { _ in }
        let result = bytes.withUnsafeBufferPointer { buf in
            SteamControllerHIDParser().parse(reportID: 0x99, report: buf.baseAddress!, length: buf.count)
        }

        XCTAssertNil(result)
    }

    func testSteamController_RightTouchpadStateNormalizesToControllerTouchpadRange() {
        let bytes = makeReport(length: 29) { p in
            writeLE32(
                SteamControllerButtonMask.rightPadTouch | SteamControllerButtonMask.rightPadClick,
                to: p,
                offset: 1
            )
            writeLE16(0x4000, to: p, offset: 23)
            writeLE16(UInt16(bitPattern: Int16(-16384)), to: p, offset: 25)
        }

        let report = bytes.withUnsafeBufferPointer { buf in
            SteamControllerHIDParser().parse(reportID: 0x45, report: buf.baseAddress!, length: buf.count)
        }
        let touchpad = report.map(SteamControllerHIDController.rightTouchpadState(from:))

        XCTAssertEqual(touchpad?.x ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(touchpad?.y ?? 0, -0.5, accuracy: 0.001)
        XCTAssertEqual(touchpad?.isTouching, true)
        XCTAssertEqual(touchpad?.isPressed, true)
    }

    func testSteamController_LeftTouchpadStateNormalizesToControllerTouchpadRange() {
        let bytes = makeReport(length: 29) { p in
            writeLE32(
                SteamControllerButtonMask.leftPadTouch | SteamControllerButtonMask.leftPadClick,
                to: p,
                offset: 1
            )
            writeLE16(UInt16(bitPattern: Int16(-8192)), to: p, offset: 17)
            writeLE16(0x2000, to: p, offset: 19)
        }

        let report = bytes.withUnsafeBufferPointer { buf in
            SteamControllerHIDParser().parse(reportID: 0x45, report: buf.baseAddress!, length: buf.count)
        }
        let touchpad = report.map(SteamControllerHIDController.leftTouchpadState(from:))

        XCTAssertEqual(touchpad?.x ?? 0, -0.25, accuracy: 0.001)
        XCTAssertEqual(touchpad?.y ?? 0, 0.25, accuracy: 0.001)
        XCTAssertEqual(touchpad?.isTouching, true)
        XCTAssertEqual(touchpad?.isPressed, true)
    }

    func testSteamController_ButtonEventsMapToControllerButtons() {
        let current = SteamControllerButtonMask.qam
            | SteamControllerButtonMask.view
            | SteamControllerButtonMask.menu
            | SteamControllerButtonMask.steam
            | SteamControllerButtonMask.leftUpperGrip
            | SteamControllerButtonMask.rightLowerGrip

        let events = SteamControllerHIDController.buttonEvents(previous: 0, current: current)

        XCTAssertTrue(events.contains(ControllerButtonEvent(button: .share, pressed: true)))
        XCTAssertTrue(events.contains(ControllerButtonEvent(button: .view, pressed: true)))
        XCTAssertTrue(events.contains(ControllerButtonEvent(button: .menu, pressed: true)))
        XCTAssertTrue(events.contains(ControllerButtonEvent(button: .xbox, pressed: true)))
        XCTAssertTrue(events.contains(ControllerButtonEvent(button: .xboxPaddle1, pressed: true)))
        XCTAssertTrue(events.contains(ControllerButtonEvent(button: .xboxPaddle4, pressed: true)))
        XCTAssertFalse(events.contains(ControllerButtonEvent(button: .leftTouchpadButton, pressed: true)))
        XCTAssertFalse(events.contains(ControllerButtonEvent(button: .rightTouchpadButton, pressed: true)))
    }

    private func writeLE16(_ value: UInt16, to p: UnsafeMutablePointer<UInt8>, offset: Int) {
        p[offset] = UInt8(value & 0xFF)
        p[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private func writeLE32(_ value: UInt32, to p: UnsafeMutablePointer<UInt8>, offset: Int) {
        p[offset] = UInt8(value & 0xFF)
        p[offset + 1] = UInt8((value >> 8) & 0xFF)
        p[offset + 2] = UInt8((value >> 16) & 0xFF)
        p[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
