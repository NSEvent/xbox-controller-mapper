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

    func testSteamController_MotionReportParsesIMUFields() {
        let bytes = makeReport(length: 54) { p in
            writeLE32(0x12345678, to: p, offset: 29)
            writeLE16(UInt16(bitPattern: Int16(-100)), to: p, offset: 33)
            writeLE16(UInt16(bitPattern: Int16(200)), to: p, offset: 35)
            writeLE16(UInt16(bitPattern: Int16(-300)), to: p, offset: 37)
            writeLE16(UInt16(bitPattern: Int16(400)), to: p, offset: 39)
            writeLE16(UInt16(bitPattern: Int16(-500)), to: p, offset: 41)
            writeLE16(UInt16(bitPattern: Int16(600)), to: p, offset: 43)
        }

        let report = bytes.withUnsafeBufferPointer { buf in
            SteamControllerHIDParser().parse(reportID: 0x45, report: buf.baseAddress!, length: buf.count)
        }

        XCTAssertEqual(report?.motion?.timestamp, 0x12345678)
        XCTAssertEqual(report?.motion?.accelX, -100)
        XCTAssertEqual(report?.motion?.accelY, 200)
        XCTAssertEqual(report?.motion?.accelZ, -300)
        XCTAssertEqual(report?.motion?.gyroX, 400)
        XCTAssertEqual(report?.motion?.gyroY, -500)
        XCTAssertEqual(report?.motion?.gyroZ, 600)
    }

    func testSteamController_HorizontalGyroUsesYawWhenRollIsSmall() {
        let result = ControllerService.steamHorizontalAimRate(gyroY: 20, gyroZ: 1000)

        XCTAssertEqual(result, 1000.0 * Config.steamGyroAimingYawBlend, accuracy: 0.001)
    }

    func testSteamController_HorizontalGyroDoesNotCancelOpposedAxes() {
        let result = ControllerService.steamHorizontalAimRate(gyroY: -1000, gyroZ: -1000)

        XCTAssertEqual(result, 1000, accuracy: 0.001)
    }

    func testSteamController_HapticTonePayloadMatchesTritonOutputLayout() {
        let payload = SteamControllerHIDController.hapticTonePayload(
            actuator: SteamControllerHIDController.leftTrackpadActuator,
            frequencyHz: 400,
            gain: -6,
            count: 6
        )

        XCTAssertEqual(payload.count, SteamControllerHIDController.hapticOutputPayloadSize)
        XCTAssertEqual(payload[0], 0)
        XCTAssertEqual(payload[1], UInt8(bitPattern: Int8(-6)))
        XCTAssertEqual(payload[2], 0x90)
        XCTAssertEqual(payload[3], 0x01)
        XCTAssertEqual(payload[4], 0x06)
        XCTAssertEqual(payload[5], 0x00)
    }

    func testSteamController_HapticOutputReportPrefixesReportID() {
        let payload = SteamControllerHIDController.hapticTonePayload(
            actuator: SteamControllerHIDController.rightTrackpadActuator,
            frequencyHz: 400,
            gain: -6,
            count: 6
        )
        let report = SteamControllerHIDController.hapticOutputReport(
            reportID: SteamControllerHIDController.hapticToneReportID,
            payload: payload
        )

        XCTAssertEqual(report.count, SteamControllerHIDController.hapticOutputReportSize)
        XCTAssertEqual(report[0], SteamControllerHIDController.hapticToneReportID)
        XCTAssertEqual(report[1], SteamControllerHIDController.rightTrackpadActuator)
        XCTAssertEqual(report[2], UInt8(bitPattern: Int8(-6)))
        XCTAssertEqual(report[3], 0x90)
        XCTAssertEqual(report[4], 0x01)
        XCTAssertEqual(report[5], 0x06)
        XCTAssertEqual(report[6], 0x00)
    }

    func testSteamController_HapticStopPayloadMatchesTritonOutputLayout() {
        let payload = SteamControllerHIDController.hapticStopPayload(
            actuator: SteamControllerHIDController.rightTrackpadActuator
        )

        XCTAssertEqual(payload.count, SteamControllerHIDController.hapticOutputPayloadSize)
        XCTAssertEqual(payload[0], 1)
        XCTAssertTrue(payload.dropFirst().allSatisfy { $0 == 0 })
    }

    func testSteamController_LizardFeatureReportMatchesTritonLayout() {
        let withoutID = SteamControllerHIDController.lizardModeFeatureReport(
            enabled: false,
            includesReportID: false
        )
        let withID = SteamControllerHIDController.lizardModeFeatureReport(
            enabled: false,
            includesReportID: true
        )

        XCTAssertEqual(withoutID.count, 64)
        XCTAssertEqual(Array(withoutID.prefix(5)), [0x87, 0x03, 0x09, 0x00, 0x00])
        XCTAssertEqual(withID.count, 64)
        XCTAssertEqual(Array(withID.prefix(6)), [0x01, 0x87, 0x03, 0x09, 0x00, 0x00])
    }

    func testSteamController_LizardActivationGateBlocksInputUntilDisabled() {
        var gate = SteamControllerLizardActivationGate()

        XCTAssertFalse(gate.canDispatchInput)
        XCTAssertTrue(gate.markDisableSucceeded())
        XCTAssertTrue(gate.canDispatchInput)
        XCTAssertFalse(gate.markDisableSucceeded())

        gate.reset()
        XCTAssertFalse(gate.canDispatchInput)
    }

    func testSteamController_LizardMouseInterfaceIsSeized() {
        XCTAssertTrue(
            SteamControllerHIDController.shouldSeizeLizardMouseInterface(
                vendorID: SteamControllerHIDParser.valveVendorID,
                productID: SteamControllerHIDParser.puckProductID,
                primaryUsagePage: SteamControllerHIDParser.genericDesktopUsagePage,
                primaryUsage: SteamControllerHIDParser.mouseUsage
            )
        )
        XCTAssertFalse(
            SteamControllerHIDController.shouldSeizeLizardMouseInterface(
                vendorID: SteamControllerHIDParser.valveVendorID,
                productID: SteamControllerHIDParser.puckProductID,
                primaryUsagePage: SteamControllerHIDParser.vendorUsagePage,
                primaryUsage: SteamControllerHIDParser.vendorCommandUsage
            )
        )
    }

    func testSteamController_HIDMatchingIncludesLizardMouseInterface() {
        let dictionaries = SteamControllerHIDParser.matchingDictionaries() as NSArray
        let expected = [
            kIOHIDVendorIDKey as String: SteamControllerHIDParser.valveVendorID,
            kIOHIDProductIDKey as String: SteamControllerHIDParser.puckProductID,
            kIOHIDDeviceUsagePageKey as String: SteamControllerHIDParser.genericDesktopUsagePage,
            kIOHIDDeviceUsageKey as String: SteamControllerHIDParser.mouseUsage,
        ] as NSDictionary

        XCTAssertTrue(dictionaries.contains(expected))
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

    func testSteamController_TouchpadTapGateSuppressesTapWhenClickArrivesAfterTouchDrops() {
        var gate = SteamControllerTouchpadTapGate()
        var taps: [TouchpadRegion] = []

        gate.queue(side: .right, region: .topRight, now: 1.0)
        gate.cancel(side: .right)
        taps.append(contentsOf: gate.flush(now: 1.0 + Config.steamTouchpadTapClickSuppressionWindow + 0.01).map { $0.1 })

        XCTAssertTrue(taps.isEmpty, "Physical pad clicks should not also dispatch tap actions")
    }

    func testSteamController_TouchpadTapTrackerStillDispatchesPlainTap() {
        var tracker = SteamControllerTouchpadTapTracker()
        var taps: [TouchpadRegion] = []

        tracker.update(
            state: SteamControllerTouchpadState(x: 0.25, y: 0.25, isTouching: true, isPressed: false),
            now: 1.0
        ) { taps.append($0) }
        tracker.update(
            state: SteamControllerTouchpadState(x: 0, y: 0, isTouching: false, isPressed: false),
            now: 1.05
        ) { taps.append($0) }

        XCTAssertEqual(taps.count, 1)
    }

    func testSteamController_TouchpadMovementHapticTrackerTicksAfterDistanceAndCooldown() {
        var tracker = SteamControllerTouchpadMovementHapticTracker()
        let step = Float(Config.steamTouchpadMovementHapticDistanceStep)
        let interval = Config.steamTouchpadMovementHapticMinInterval

        XCTAssertFalse(tracker.update(
            state: SteamControllerTouchpadState(x: 0, y: 0, isTouching: true, isPressed: false),
            now: 1.0
        ))
        XCTAssertFalse(tracker.update(
            state: SteamControllerTouchpadState(x: step * 0.5, y: 0, isTouching: true, isPressed: false),
            now: 1.0 + interval
        ))
        XCTAssertTrue(tracker.update(
            state: SteamControllerTouchpadState(x: step * 1.1, y: 0, isTouching: true, isPressed: false),
            now: 1.0 + interval
        ))
        XCTAssertFalse(tracker.update(
            state: SteamControllerTouchpadState(x: step * 2.2, y: 0, isTouching: true, isPressed: false),
            now: 1.0 + interval + 0.001
        ))
        XCTAssertFalse(tracker.update(
            state: SteamControllerTouchpadState(x: step * 2.2, y: 0, isTouching: true, isPressed: false),
            now: 1.0 + interval * 2.0 + 0.001
        ))
        XCTAssertTrue(tracker.update(
            state: SteamControllerTouchpadState(x: step * 3.3, y: 0, isTouching: true, isPressed: false),
            now: 1.0 + interval * 2.0 + 0.001
        ))
    }

    func testSteamController_TouchpadMovementHapticTrackerIgnoresRestingJitter() {
        var tracker = SteamControllerTouchpadMovementHapticTracker()
        let jitter = Float(Config.steamTouchpadMovementHapticDistanceStep * 0.35)

        XCTAssertFalse(tracker.update(
            state: SteamControllerTouchpadState(x: 0, y: 0, isTouching: true, isPressed: false),
            now: 1.0
        ))

        for index in 1...12 {
            let sign: Float = index.isMultiple(of: 2) ? 1 : -1
            XCTAssertFalse(tracker.update(
                state: SteamControllerTouchpadState(
                    x: jitter * sign,
                    y: jitter * -sign,
                    isTouching: true,
                    isPressed: false
                ),
                now: 1.0 + Double(index) * Config.steamTouchpadMovementHapticMinInterval
            ))
        }
    }

    func testSteamController_TouchpadMovementHapticTrackerSuppressesPressedDrag() {
        var tracker = SteamControllerTouchpadMovementHapticTracker()
        let step = Float(Config.steamTouchpadMovementHapticDistanceStep)

        _ = tracker.update(
            state: SteamControllerTouchpadState(x: 0, y: 0, isTouching: true, isPressed: false),
            now: 1.0
        )
        XCTAssertFalse(tracker.update(
            state: SteamControllerTouchpadState(x: step * 2.0, y: 0, isTouching: true, isPressed: true),
            now: 1.1
        ))
        XCTAssertFalse(tracker.update(
            state: SteamControllerTouchpadState(x: step * 2.5, y: 0, isTouching: false, isPressed: false),
            now: 1.2
        ))
        XCTAssertFalse(tracker.update(
            state: SteamControllerTouchpadState(x: step * 3.0, y: 0, isTouching: true, isPressed: false),
            now: 1.3
        ))
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
