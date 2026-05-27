import XCTest
import CoreGraphics
@testable import ControllerKeys

final class MappingEngineTouchpadCoverageTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-touchpad-tests-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            controllerService = ControllerService(enableHardwareMonitoring: false)
            profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
            appMonitor = AppMonitor()
            mockInputSimulator = MockInputSimulator()
            controllerService.storage.isSteamController = false

            mappingEngine = MappingEngine(
                controllerService: controllerService,
                profileManager: profileManager,
                appMonitor: appMonitor,
                inputSimulator: mockInputSimulator
            )
            mappingEngine.enable()
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            mappingEngine?.disable()
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        // Reset zoom level to prevent tests from leaving the system in a zoomed state.
        // Posts Cmd+0 (View > Actual Size) which resets zoom in most apps.
        if let source = CGEventSource(stateID: .hidSystemState) {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x1D, keyDown: true)  // 0x1D = '0'
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x1D, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cghidEventTap)
        }

        await MainActor.run {
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.onLeftStickMoved = nil
            controllerService?.onRightStickMoved = nil
            controllerService?.onTouchpadMoved = nil
            controllerService?.onTouchpadGesture = nil
            controllerService?.onTouchpadTap = nil
            controllerService?.onTouchpadTwoFingerTap = nil
            controllerService?.onTouchpadLongTap = nil
            controllerService?.onTouchpadTwoFingerLongTap = nil
            controllerService?.cleanup()

            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
    }

    private func waitForTasks(_ delay: TimeInterval = 0.3) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    func testRightStickScrollModeGeneratesScrollEvents() async throws {
        await MainActor.run {
            var profile = Profile(name: "RightScroll", buttonMappings: [:])
            profile.joystickSettings.rightStickMode = .scroll
            profile.joystickSettings.scrollDeadzone = 0.05
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.15)

        await MainActor.run {
            controllerService.setRightStickForTesting(CGPoint(x: 0.0, y: 0.9))
        }
        await waitForTasks(0.35)

        await MainActor.run {
            let hasNonZeroScroll = mockInputSimulator.events.contains { event in
                if case .scroll(let dx, let dy) = event {
                    return abs(dx) > 0.1 || abs(dy) > 0.1
                }
                return false
            }
            XCTAssertTrue(hasNonZeroScroll, "Right stick scroll mode should emit non-zero scroll events")
        }
    }

    func testTouchpadMovementGeneratesMouseMovement() async throws {
        await MainActor.run {
            var profile = Profile(name: "TouchMove", buttonMappings: [:])
            profile.joystickSettings.touchpadDeadzone = 0.00001
            profile.joystickSettings.touchpadSmoothing = 0
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadMoved?(CGPoint(x: 0.6, y: 0.4))
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasMove = mockInputSimulator.events.contains { event in
                if case .moveMouse(let dx, let dy) = event {
                    return abs(dx) > 0.1 || abs(dy) > 0.1
                }
                return false
            }
            XCTAssertTrue(hasMove, "Touchpad movement should emit mouse movement")
        }
    }

    func testTouchpadMovementSuppressedDuringTwoFingerGesture() async throws {
        await MainActor.run {
            var profile = Profile(name: "TouchSuppressed", buttonMappings: [:])
            profile.joystickSettings.touchpadDeadzone = 0.00001
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true
                )
            )
            mockInputSimulator.clearEvents()
            controllerService.onTouchpadMoved?(CGPoint(x: 0.7, y: 0.7))
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasMove = mockInputSimulator.events.contains { event in
                if case .moveMouse = event { return true }
                return false
            }
            XCTAssertFalse(hasMove, "Touchpad movement should be suppressed while two-finger gesture is active")

            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: false,
                    isSecondaryTouching: false
                )
            )
        }
    }

    func testTouchpadTapDoubleTapExecutesAlternateMapping() async throws {
        await MainActor.run {
            let mapping = KeyMapping(
                keyCode: KeyCodeMapping.tab,
                doubleTapMapping: DoubleTapMapping(keyCode: KeyCodeMapping.return, threshold: 0.12)
            )
            profileManager.setActiveProfile(Profile(name: "TouchDoubleTap", buttonMappings: [.touchpadTap: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadTap?()
        }
        await waitForTasks(0.04)
        await MainActor.run {
            controllerService.onTouchpadTap?()
        }
        await waitForTasks(0.25)

        await MainActor.run {
            let returnPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.return }
                return false
            }.count
            let tabPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.tab }
                return false
            }.count

            XCTAssertEqual(returnPresses, 1, "Double tap should execute return mapping once")
            XCTAssertEqual(tabPresses, 0, "Single-tap fallback should be cancelled by double tap")
        }
    }

    func testTouchpadLongTapCancelsPendingTapAndExecutesLongHold() async throws {
        await MainActor.run {
            let mapping = KeyMapping(
                keyCode: KeyCodeMapping.tab,
                longHoldMapping: LongHoldMapping(keyCode: KeyCodeMapping.escape, threshold: 0.2),
                doubleTapMapping: DoubleTapMapping(keyCode: KeyCodeMapping.return, threshold: 0.2)
            )
            profileManager.setActiveProfile(Profile(name: "TouchLongTap", buttonMappings: [.touchpadTap: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadTap?()      // schedules pending single tap
        }
        await waitForTasks(0.05)
        await MainActor.run {
            controllerService.onTouchpadLongTap?()  // should cancel pending tap and run long-hold action
        }
        await waitForTasks(0.30)

        await MainActor.run {
            let escapePresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.escape }
                return false
            }.count
            let tabPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.tab }
                return false
            }.count

            XCTAssertEqual(escapePresses, 1, "Long tap should execute long-hold mapping")
            XCTAssertEqual(tabPresses, 0, "Pending single tap should be cancelled by long tap")
        }
    }

    func testTouchpadTwoFingerLongTapCancelsPendingTapAndExecutesLongHold() async throws {
        await MainActor.run {
            let mapping = KeyMapping(
                keyCode: KeyCodeMapping.mouseRightClick,
                longHoldMapping: LongHoldMapping(keyCode: KeyCodeMapping.escape, threshold: 0.2),
                doubleTapMapping: DoubleTapMapping(keyCode: KeyCodeMapping.return, threshold: 0.2)
            )
            profileManager.setActiveProfile(Profile(name: "TouchTwoFingerLongTap", buttonMappings: [.touchpadTwoFingerTap: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadTwoFingerTap?()
        }
        await waitForTasks(0.05)
        await MainActor.run {
            controllerService.onTouchpadTwoFingerLongTap?()
        }
        await waitForTasks(0.30)

        await MainActor.run {
            let escapePresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.escape }
                return false
            }.count
            let rightClickPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.mouseRightClick }
                return false
            }.count

            XCTAssertEqual(escapePresses, 1, "Two-finger long tap should execute long-hold mapping")
            XCTAssertEqual(rightClickPresses, 0, "Pending two-finger single tap should be cancelled by long tap")
        }
    }

    func testTouchpadPinchZoomInUsesCmdEqualWhenNativeZoomDisabled() async throws {
        await MainActor.run {
            var profile = Profile(name: "TouchPinchIn", buttonMappings: [:])
            profile.joystickSettings.touchpadUseNativeZoom = false
            profile.joystickSettings.touchpadSmoothing = 0
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0.24,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true
                )
            )
        }
        await waitForTasks(0.15)

        await MainActor.run {
            let plusPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, let flags) = event {
                    return keyCode == KeyCodeMapping.equal && flags.contains(.maskCommand)
                }
                return false
            }.count
            XCTAssertGreaterThan(plusPresses, 0, "Pinch out should trigger Cmd+Equal zoom-in keypress")

            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: false,
                    isSecondaryTouching: false
                )
            )
        }
    }

    func testTouchpadPinchZoomOutUsesCmdMinusWhenNativeZoomDisabled() async throws {
        await MainActor.run {
            var profile = Profile(name: "TouchPinchOut", buttonMappings: [:])
            profile.joystickSettings.touchpadUseNativeZoom = false
            profile.joystickSettings.touchpadSmoothing = 0
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: -0.24,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true
                )
            )
        }
        await waitForTasks(0.15)

        await MainActor.run {
            let minusPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, let flags) = event {
                    return keyCode == KeyCodeMapping.minus && flags.contains(.maskCommand)
                }
                return false
            }.count
            XCTAssertGreaterThan(minusPresses, 0, "Pinch in should trigger Cmd+Minus zoom-out keypress")

            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: false,
                    isSecondaryTouching: false
                )
            )
        }
    }

    func testSteamTouchpadPinchRequiresLargerDistanceToTriggerZoom() async throws {
        await MainActor.run {
            var profile = Profile(name: "SteamTouchPinch", buttonMappings: [:])
            profile.joystickSettings.touchpadUseNativeZoom = false
            profile.joystickSettings.touchpadSmoothing = 0
            profileManager.setActiveProfile(profile)
            controllerService.storage.isSteamController = true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: Config.touchpadPinchDeadzone + 0.02,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true,
                    primaryDelta: CGPoint(x: 0.04, y: 0),
                    secondaryDelta: CGPoint(x: -0.04, y: 0)
                )
            )
        }
        await waitForTasks(0.15)

        await MainActor.run {
            let plusPressesBeforeThreshold = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, let flags) = event {
                    return keyCode == KeyCodeMapping.equal && flags.contains(.maskCommand)
                }
                return false
            }.count
            XCTAssertEqual(plusPressesBeforeThreshold, 0, "Steam two-pad pinch should ignore small distance changes")
            mockInputSimulator.clearEvents()

            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: Config.steamTouchpadPinchDeadzone + 0.02,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true,
                    primaryDelta: CGPoint(x: 0.06, y: 0),
                    secondaryDelta: CGPoint(x: -0.06, y: 0)
                )
            )
        }
        await waitForTasks(0.15)

        await MainActor.run {
            let plusPressesAfterThreshold = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, let flags) = event {
                    return keyCode == KeyCodeMapping.equal && flags.contains(.maskCommand)
                }
                return false
            }.count
            XCTAssertGreaterThan(plusPressesAfterThreshold, 0, "Steam two-pad pinch should trigger after the larger threshold")

            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: false,
                    isSecondaryTouching: false
                )
            )
        }
    }

    func testTouchpadPanGestureProducesScroll() async throws {
        await MainActor.run {
            var profile = Profile(name: "TouchPan", buttonMappings: [:])
            profile.joystickSettings.touchpadUseNativeZoom = false
            profile.joystickSettings.touchpadSmoothing = 0
            profile.joystickSettings.touchpadPanSensitivity = 1.0
            profile.joystickSettings.touchpadZoomToPanRatio = 5.0
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        await waitForTasks(0.15)

        await MainActor.run {
            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: CGPoint(x: 0.9, y: 0.7),
                    distanceDelta: 0.0,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true
                )
            )
        }
        await waitForTasks(0.05)
        await MainActor.run {
            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: CGPoint(x: 0.9, y: 0.7),
                    distanceDelta: 0.0,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true
                )
            )
        }
        await waitForTasks(0.35)

        await MainActor.run {
            let nonZeroScrollCount = mockInputSimulator.events.filter { event in
                if case .scroll(let dx, let dy) = event {
                    return abs(dx) > 0.1 || abs(dy) > 0.1
                }
                return false
            }.count
            XCTAssertGreaterThan(nonZeroScrollCount, 0, "Two-finger pan should emit non-zero scroll deltas")

            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: false,
                    isSecondaryTouching: false
                )
            )
        }
        await waitForTasks(0.1)
    }

    func testSteamTwoPadPanDoesNotScroll() async throws {
        await MainActor.run {
            var profile = Profile(name: "SteamNoPan", buttonMappings: [:])
            profile.joystickSettings.touchpadUseNativeZoom = false
            profile.joystickSettings.touchpadSmoothing = 0
            profile.joystickSettings.touchpadPanSensitivity = 1.0
            profile.joystickSettings.touchpadZoomToPanRatio = 5.0
            profileManager.setActiveProfile(profile)
            controllerService.storage.isSteamController = true
            controllerService.isConnected = true
        }
        await waitForTasks(0.15)

        await MainActor.run {
            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: CGPoint(x: 0.9, y: 0.7),
                    distanceDelta: 0,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true,
                    primaryDelta: CGPoint(x: 0.1, y: 0.1),
                    secondaryDelta: CGPoint(x: 0.1, y: 0.1)
                )
            )
        }
        await waitForTasks(0.35)

        await MainActor.run {
            let nonZeroScrollCount = mockInputSimulator.events.filter { event in
                if case .scroll(let dx, let dy) = event {
                    return abs(dx) > 0.1 || abs(dy) > 0.1
                }
                return false
            }.count
            XCTAssertEqual(nonZeroScrollCount, 0, "Steam two-pad motion should not fall through to scroll")
        }
    }

    func testSteamOneRestingPadDoesNotSuppressTouchpadMouse() async throws {
        await MainActor.run {
            var profile = Profile(name: "SteamRestingPad", buttonMappings: [:])
            profile.joystickSettings.touchpadDeadzone = 0.00001
            profile.joystickSettings.touchpadSmoothing = 0
            profileManager.setActiveProfile(profile)
            controllerService.storage.isSteamController = true
        }
        await waitForTasks(0.15)

        await MainActor.run {
            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: CGPoint(x: 0.05, y: 0),
                    distanceDelta: 0,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true,
                    primaryDelta: CGPoint(x: 0.1, y: 0),
                    secondaryDelta: .zero
                )
            )
            mockInputSimulator.clearEvents()
            controllerService.onTouchpadMoved?(CGPoint(x: 0.7, y: 0.7))
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasMove = mockInputSimulator.events.contains { event in
                if case .moveMouse = event { return true }
                return false
            }
            XCTAssertTrue(hasMove, "Steam one-pad movement should continue when the other pad is only resting")
        }
    }

    func testSteamTwoMovingPadsSuppressTouchpadMouse() async throws {
        await MainActor.run {
            var profile = Profile(name: "SteamMovingPads", buttonMappings: [:])
            profile.joystickSettings.touchpadDeadzone = 0.00001
            profile.joystickSettings.touchpadSmoothing = 0
            profileManager.setActiveProfile(profile)
            controllerService.storage.isSteamController = true
        }
        await waitForTasks(0.15)

        await MainActor.run {
            controllerService.onTouchpadGesture?(
                TouchpadGesture(
                    centerDelta: CGPoint(x: 0.02, y: 0),
                    distanceDelta: Config.steamTouchpadPinchDeadzone + 0.02,
                    isPrimaryTouching: true,
                    isSecondaryTouching: true,
                    primaryDelta: CGPoint(x: 0.1, y: 0),
                    secondaryDelta: CGPoint(x: -0.1, y: 0)
                )
            )
            mockInputSimulator.clearEvents()
            controllerService.onTouchpadMoved?(CGPoint(x: 0.7, y: 0.7))
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasMove = mockInputSimulator.events.contains { event in
                if case .moveMouse = event { return true }
                return false
            }
            XCTAssertFalse(hasMove, "Steam two-pad gestures should suppress touchpad mouse movement")
        }
    }
}
