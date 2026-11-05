import XCTest
import CoreGraphics
@testable import ControllerKeys

final class WiimotePointerTests: XCTestCase {
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

    func testReacquiringSensorBarReanchorsWithoutCursorJump() {
        let filter = WiimotePointerState()
        XCTAssertNil(filter.advance(target: CGPoint(x: 100, y: 200), baseAlpha: 0.25, blobCount: 2, at: 10))
        XCTAssertNotNil(filter.advance(target: CGPoint(x: 110, y: 210), baseAlpha: 0.25, blobCount: 2, at: 10.01))
        XCTAssertNil(filter.advance(target: CGPoint(x: 800, y: 600), baseAlpha: 0.25, blobCount: 2, at: 11))
        let delta = filter.advance(target: CGPoint(x: 801, y: 601), baseAlpha: 0.25, blobCount: 2, at: 11.01)
        XCTAssertLessThan(abs(delta?.x ?? 100), 1)
        XCTAssertLessThan(abs(delta?.y ?? 100), 1)
    }

    func testBriefDropoutRetainsTrackingButBlobCountChangeReanchors() {
        let filter = WiimotePointerState()
        _ = filter.advance(target: .zero, baseAlpha: 0.25, blobCount: 2, at: 10)
        XCTAssertTrue(filter.irSeenRecently(now: 10.1, grace: 0.4))
        XCTAssertNotNil(filter.advance(target: CGPoint(x: 5, y: 0), baseAlpha: 0.25, blobCount: 2, at: 10.1))
        XCTAssertNil(filter.advance(target: CGPoint(x: 200, y: 0), baseAlpha: 0.25, blobCount: 1, at: 10.2))
        filter.reset()
        XCTAssertFalse(filter.irSeenRecently(now: 10.3, grace: 0.4))
        XCTAssertNil(filter.advance(target: .zero, baseAlpha: 0.25, blobCount: 1, at: 10.3))
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
