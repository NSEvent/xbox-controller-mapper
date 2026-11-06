import XCTest
import CoreGraphics
@testable import ControllerKeys

final class WiimotePointerTests: XCTestCase {
	func testHIDConnectWaitsForPairingDisconnectThenRetriesWithoutInputDevice() {
		var attempt = WiimoteHIDConnectionAttempt(startedAt: 10)
		XCTAssertEqual(attempt.advance(at: 10, hasHIDDevice: false), .wait)
		XCTAssertEqual(attempt.advance(at: 10.49, hasHIDDevice: false), .wait)
		XCTAssertEqual(attempt.advance(at: 10.5, hasHIDDevice: false), .request)
		XCTAssertEqual(attempt.advance(at: 12.49, hasHIDDevice: false), .wait)
		XCTAssertEqual(attempt.advance(at: 12.5, hasHIDDevice: false), .request)
	}

	func testHIDConnectRequiresStableInputAttachment() {
		var attempt = WiimoteHIDConnectionAttempt(startedAt: 10)
		XCTAssertEqual(attempt.advance(at: 10.1, hasHIDDevice: true), .wait)
		XCTAssertEqual(attempt.advance(at: 10.5, hasHIDDevice: true), .wait)
		XCTAssertEqual(attempt.advance(at: 11, hasHIDDevice: false), .request)
		XCTAssertEqual(attempt.advance(at: 11.25, hasHIDDevice: true), .wait)
		XCTAssertEqual(attempt.advance(at: 11.75, hasHIDDevice: true), .wait)
		XCTAssertEqual(attempt.advance(at: 12, hasHIDDevice: true), .connected)
		XCTAssertEqual(attempt.advance(at: 12.25, hasHIDDevice: false), .connected)
	}

	func testHIDConnectStopsRetryingAtDeadline() {
		var attempt = WiimoteHIDConnectionAttempt(startedAt: 10)
		XCTAssertEqual(attempt.advance(at: 10.5, hasHIDDevice: false), .request)
		XCTAssertEqual(attempt.advance(at: 25, hasHIDDevice: false), .timedOut)
		XCTAssertEqual(attempt.advance(at: 30, hasHIDDevice: true), .timedOut)
	}

	func testHIDConnectDoesNotMistakeLastMomentTransientAttachmentForSuccess() {
		var attempt = WiimoteHIDConnectionAttempt(startedAt: 10)
		XCTAssertEqual(attempt.advance(at: 24.75, hasHIDDevice: true), .wait)
		XCTAssertEqual(attempt.advance(at: 25, hasHIDDevice: true), .timedOut)
	}

    func testIRReportDecodesTenBitCoordinatesAndIgnoresMissingSlots() {
        // Two emitters at (300, 400) and (700, 500), followed by empty slots.
        let bytes: [UInt8] = [0x33, 0, 8, 128, 128, 154,
                             44, 144, 0x55, 188, 244, 0x66,
                             255, 255, 255, 255, 255, 255]
        let result = bytes.withUnsafeBufferPointer {
            WiimoteHIDParser().parse(reportID: 0x33, report: $0.baseAddress!, length: $0.count)
        }
        XCTAssertEqual(result?.wiimoteButtons, .a)
        XCTAssertEqual(result?.wiimoteIRPoints?.map(\.x), [300, 700])
        XCTAssertEqual(result?.wiimoteIRPoints?.map(\.y), [400, 500])
        XCTAssertEqual(result?.wiimoteIRPoints?.map(\.size), [5, 6])
    }

    func testTruncatedIRReportNeverReadsBeyondBuffer() {
        let bytes: [UInt8] = [0x33, 0, 4, 128, 128, 128, 20]
        let result = bytes.withUnsafeBufferPointer {
            WiimoteHIDParser().parse(reportID: 0x33, report: $0.baseAddress!, length: $0.count)
        }
        XCTAssertEqual(result?.wiimoteButtons, .b)
        XCTAssertNil(result?.wiimoteIRPoints)
    }

    func testIRReportDropsOutOfFieldAndZeroFilledSlots() {
        // Valid (300, 400); zero-filled slot; Y = 1000 (outside 768); empty.
        let bytes: [UInt8] = [0x33, 0, 0, 128, 128, 154,
                             44, 144, 0x55, 0, 0, 0,
                             0xE8, 0xE8, 0xC5, 255, 255, 255]
        let result = bytes.withUnsafeBufferPointer {
            WiimoteHIDParser().parse(reportID: 0x33, report: $0.baseAddress!, length: $0.count)
        }
        XCTAssertEqual(result?.wiimoteIRPoints, [WiimoteIRPoint(x: 300, y: 400, size: 5)])
    }

    func testAckReportDecodesAnsweredReportAndResult() {
        let bytes: [UInt8] = [0x22, 0, 8, 0x16, 0x03]
        let result = bytes.withUnsafeBufferPointer {
            WiimoteHIDParser().parse(reportID: 0x22, report: $0.baseAddress!, length: $0.count)
        }
        XCTAssertEqual(result?.wiimoteAckReportID, 0x16)
        XCTAssertEqual(result?.wiimoteAckError, 0x03)
        XCTAssertNil(result?.wiimoteButtons)
    }

    // MARK: IR tracking (1024×768 screen: at 1× gain 1 camera px = 1 screen px;
    // tests default to 1.25× so near-center anchors stay at the base scale)

    private let screen = CGRect(x: 0, y: 0, width: 1024, height: 768)
    private let start = CGPoint(x: 500, y: 400)

    private struct Rig {
        var tracker = WiimoteIRTracker()
        var cursor: CGPoint
        var time: TimeInterval = 10
        let screen: CGRect
        let gain: CGFloat

        /// Feed the same blobs for `reports` reports (100 Hz) so smoothing settles.
        mutating func feed(_ points: [CGPoint], reports: Int = 80) {
            let start = cursor
            for _ in 0..<reports {
                time += 0.01
                if let delta = tracker.update(
                    blobs: points.map { WiimoteIRTracker.Blob(point: $0, size: 4) },
                    at: time, baseAlpha: 0.25, gain: gain, bounds: screen,
                    currentCursor: { start }
                ) {
                    cursor.x += delta.x
                    cursor.y += delta.y
                }
            }
        }
    }

    private func rig(gain: CGFloat = 1.25, cursor: CGPoint? = nil) -> Rig {
        Rig(cursor: cursor ?? start, screen: screen, gain: gain)
    }

    private func assertCursor(_ rig: Rig, _ x: CGFloat, _ y: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rig.cursor.x, x, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(rig.cursor.y, y, accuracy: 0.5, file: file, line: line)
    }

    private func bar(midX: CGFloat, midY: CGFloat, halfWidth: CGFloat = 100) -> [CGPoint] {
        [CGPoint(x: midX - halfWidth, y: midY), CGPoint(x: midX + halfWidth, y: midY)]
    }

    func testIRAimIsMirroredAndAbsoluteThroughEdgeClamping() {
        var r = rig(gain: 2)
        r.feed(bar(midX: 512, midY: 384))
        assertCursor(r, 500, 400)
        // Pointing right moves the bar image left; pointing down moves it down.
        r.feed(bar(midX: 462, midY: 404))
        assertCursor(r, 600, 440)
        // Far past the left edge clamps there...
        r.feed(bar(midX: 900, midY: 384))
        assertCursor(r, 0, 400)
        // ...and aiming back at the start returns to the exact start pixel.
        r.feed(bar(midX: 512, midY: 384))
        assertCursor(r, 500, 400)
    }

    func testOneBarEndDroppingOutNeitherMovesNorStallsTheCursor() {
        var r = rig()
        let full = bar(midX: 512, midY: 384)
        r.feed(full)
        r.feed([full[0]])
        assertCursor(r, 500, 400)
        r.feed([full[1]])
        assertCursor(r, 500, 400)
        // Pitching with only one end visible still tracks vertically.
        r.feed([CGPoint(x: full[0].x, y: full[0].y + 120)])
        assertCursor(r, 500, 550)
        r.feed(bar(midX: 512, midY: 504))
        assertCursor(r, 500, 550)
    }

    func testRollingTheRemoteDoesNotMoveTheCursor() {
        var r = rig()
        let level = bar(midX: 612, midY: 484)
        r.feed(level)
        let angle = CGFloat.pi / 6
        let center = WiimoteIRTracker.cameraCenter
        let rolled = level.map { p -> CGPoint in
            let vx = p.x - center.x, vy = p.y - center.y
            return CGPoint(x: center.x + vx * cos(angle) - vy * sin(angle),
                           y: center.y + vx * sin(angle) + vy * cos(angle))
        }
        r.feed(rolled)
        assertCursor(r, 500, 400)
    }

    func testStrayLightAndSplitBarEndDoNotHijackTheMidpoint() {
        var r = rig()
        let full = bar(midX: 512, midY: 384)
        r.feed(full)
        r.feed(full + [CGPoint(x: 300, y: 650)])
        assertCursor(r, 500, 400)
        r.feed(full + [CGPoint(x: full[0].x + 6, y: full[0].y + 2)])
        assertCursor(r, 500, 400)
    }

    func testLoneBlobAnchorHandsOffToTheBarWithoutJumping() {
        var r = rig()
        r.feed([CGPoint(x: 412, y: 384)])
        r.feed(bar(midX: 512, midY: 384))
        assertCursor(r, 500, 400)
        r.feed(bar(midX: 412, midY: 384))
        assertCursor(r, 625, 400)
    }

    func testReacquiringAfterDropoutSnapsToTheAbsoluteAim() {
        var r = rig()
        r.feed(bar(midX: 512, midY: 384))
        r.time += 1.0
        r.feed(bar(midX: 462, midY: 384), reports: 1)
        assertCursor(r, 562.5, 400)
    }

    func testEveryScreenEdgeIsReachableBeforeTheBarLeavesTheCameraFrame() {
        // Anchored low on screen while the bar sits high in the frame: at the
        // base scale the top of the screen would need the bar to move 560px
        // up a frame with only 300px of room — an invisible ceiling.
        var r = rig(cursor: CGPoint(x: 500, y: 700))
        r.feed(bar(midX: 512, midY: 300))
        r.feed(bar(midX: 512, midY: 60))
        XCTAssertLessThan(r.cursor.y, 60, "most of the way up with the bar still in frame")
        r.feed(bar(midX: 512, midY: 40))
        assertCursor(r, 500, 0)
        // The roomy direction keeps the base scale, and the mapping is still
        // absolute: returning to the anchor aim returns to the anchor pixel.
        r.feed(bar(midX: 512, midY: 350))
        assertCursor(r, 500, 762.5)
        r.feed(bar(midX: 512, midY: 300))
        assertCursor(r, 500, 700)
    }

    func testTiltSteersOnlyBeforeTheSensorBarIsFirstSeen() {
        let state = WiimotePointerState()
        state.reset(at: 10)
        XCTAssertTrue(state.tiltAllowed(irEnabled: false, now: 10))
        XCTAssertFalse(state.tiltAllowed(irEnabled: true, now: 10.5), "camera still initializing")
        XCTAssertTrue(state.tiltAllowed(irEnabled: true, now: 11.1), "no sensor bar at all")
        _ = state.irDelta(points: [WiimoteIRPoint(x: 400, y: 300, size: 3)], baseAlpha: 0.25, gain: 1,
                          at: 11.2, bounds: screen, currentCursor: { CGPoint(x: 500, y: 400) })
        XCTAssertFalse(state.tiltAllowed(irEnabled: true, now: 30), "IR lost: hold, never tilt")
        XCTAssertTrue(state.tiltAllowed(irEnabled: false, now: 30))
        state.reset(at: 40)
        XCTAssertTrue(state.tiltAllowed(irEnabled: true, now: 41.1))
    }

    func testPairingOnlyRecognizesNintendoWiiRemotes() {
        XCTAssertTrue(WiimotePairingService.isWiiRemoteName("Nintendo RVL-CNT-01"))
        XCTAssertTrue(WiimotePairingService.isWiiRemoteName("Nintendo RVL-CNT-01-TR"))
        for name: String? in [nil, "", "Magic Keyboard", "Pro Controller", "Other RVL-CNT-01"] {
            XCTAssertFalse(WiimotePairingService.isWiiRemoteName(name))
        }
    }
}

final class WiimoteMappingTests: MappingEngineTestCase {
    func testToggleSurvivesReleaseAndSecondTapStopsPointer() async {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Wii toggle", buttonMappings: [
                .b: KeyMapping(keyCode: KeyCodeMapping.wiimotePointerToggle)
            ]))
        }
        await waitForTasks(0.05)
        for expected in [true, false] {
            await MainActor.run {
                controllerService.emitInputEvent(.buttonPressed(.b))
                controllerService.emitInputEvent(.buttonReleased(.b, holdDuration: 0.1))
            }
            await waitForTasks(0.1)
            await assertEngaged(expected)
        }
    }

    func testDisableClearsToggleEvenWhenPressUpdateIsStillQueued() async {
        await MainActor.run {
            mappingEngine.handleWiimotePointerPressed(.b, toggle: true)
            mappingEngine.disable()
        }
        await waitForTasks(0.1)
        await assertEngaged(false)
        await MainActor.run { mappingEngine.enable() }
        await waitForTasks(0.1)
        await assertEngaged(false)
    }

    func testSensorBarProfileImportsWithToggleAndDragBindings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let profile = try ProfileTransferService.importProfile(from: root.appendingPathComponent("community-profiles/Wii Sensor Bar.json"))
        XCTAssertEqual(profile.controllerPreviewLayout, .wiimote)
        XCTAssertEqual(profile.buttonMappings[.b]?.keyCode, KeyCodeMapping.wiimotePointerToggle)
        XCTAssertEqual(profile.buttonMappings[.a]?.keyCode, KeyCodeMapping.mouseLeftClick)
        XCTAssertEqual(profile.buttonMappings[.a]?.isHoldModifier, true)
    }

    private func engage() async {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Wii test", buttonMappings: [
                .b: KeyMapping(keyCode: KeyCodeMapping.wiimotePointerHold),
                .a: KeyMapping(keyCode: KeyCodeMapping.wiimotePointerHold)
            ]))
        }
        await waitForTasks(0.05)
        await MainActor.run { controllerService.emitInputEvent(.buttonPressed(.b)) }
        await waitForTasks(0.1)
        await assertEngaged(true)
    }

    private func assertEngaged(_ expected: Bool, file: StaticString = #filePath, line: UInt = #line) async {
        await MainActor.run {
            XCTAssertEqual(controllerService.storage.lock.withLock {
                controllerService.storage.wiimotePointerEngaged
            }, expected, file: file, line: line)
        }
    }

    func testReleaseStopsPointerWithoutPostingVirtualKey() async {
        await engage()
        await MainActor.run { controllerService.emitInputEvent(.buttonReleased(.b, holdDuration: 0.1)) }
        await waitForTasks(0.1)
        await assertEngaged(false)
        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.events.contains {
                if case .pressKey(let key, _) = $0 { return key == KeyCodeMapping.wiimotePointerHold }
                return false
            })
        }
    }

    func testDisableStopsPointerAndReenableDoesNotResumeOldHold() async {
        await engage()
        await MainActor.run { mappingEngine.disable() }
        await waitForTasks(0.1)
        await assertEngaged(false)
        await MainActor.run { mappingEngine.enable() }
        await waitForTasks(0.1)
        await assertEngaged(false)
    }

    func testLockStopsPointerAndUnlockDoesNotResumeOldHold() async {
        await engage()
        _ = mappingEngine.performLockToggle()
        await waitForTasks(0.1)
        await assertEngaged(false)
        _ = mappingEngine.performLockToggle()
        await waitForTasks(0.1)
        await assertEngaged(false)
    }

    func testProfileSwitchAndDisconnectStopPointer() async {
        await engage()
        await MainActor.run { profileManager.setActiveProfile(Profile(name: "Other")) }
        await waitForTasks(0.1)
        await assertEngaged(false)
        await engage()
        mappingEngine.resetRemoteControllerInputState()
        await waitForTasks(0.1)
        await assertEngaged(false)
    }
}
