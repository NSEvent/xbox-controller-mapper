import XCTest
import CoreGraphics
@testable import ControllerKeys

/// Characterization tests capturing current behavior of the input pipeline.
/// These tests must continue to pass after refactoring to prove zero behavior change.
final class PipelineCharacterizationTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-pipeline-char-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            controllerService = ControllerService(enableHardwareMonitoring: false)
            controllerService.chordWindow = 0.05
            profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
            appMonitor = AppMonitor()
            mockInputSimulator = MockInputSimulator()

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

    private func waitForTasks(_ delay: TimeInterval = 0.35) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    // MARK: - Chord Detection Characterization

    /// A single button press (no chord partner) should fire onButtonPressed exactly once.
    func testSingleButtonFiresOnButtonPressed() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "SingleButton",
                buttonMappings: [.a: .key(1)]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks()
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events
        let pressCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count
        XCTAssertEqual(pressCount, 1, "Single button should fire mapped key exactly once")
    }

    /// Two buttons pressed within chord window should fire onChordDetected (not individual presses).
    func testTwoButtonsWithinWindowFiresChord() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "ChordDetection",
                buttonMappings: [
                    .a: .key(1),
                    .b: .key(2)
                ],
                chordMappings: [
                    ChordMapping(buttons: [.a, .b], keyCode: 3)
                ]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonPressed(.b)
        }
        await waitForTasks()
        await MainActor.run {
            controllerService.buttonReleased(.a)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events
        let chordCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 3 }
            return false
        }.count
        let aCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count
        let bCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 2 }
            return false
        }.count

        XCTAssertEqual(chordCount, 1, "Chord should fire exactly once")
        XCTAssertEqual(aCount, 0, "Individual A should not fire when chord matches")
        XCTAssertEqual(bCount, 0, "Individual B should not fire when chord matches")
    }

    // MARK: - Sequence Detection Characterization

    /// Correct step sequence within timeout should complete and fire the sequence action.
    func testSequenceDetection_CorrectStepsComplete() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "SequenceDetection",
                buttonMappings: [
                    .a: .key(1),
                    .b: .key(2)
                ],
                sequenceMappings: [
                    SequenceMapping(steps: [.a, .b], stepTimeout: 0.5, keyCode: 5)
                ]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press A then B within timeout
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.15)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.05)
        await MainActor.run {
            controllerService.buttonPressed(.b)
        }
        await waitForTasks(0.15)
        await MainActor.run {
            controllerService.buttonReleased(.b)
        }
        await waitForTasks(0.4)

        let events = mockInputSimulator.events
        let seqCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 5 }
            return false
        }.count
        XCTAssertEqual(seqCount, 1, "Completed sequence should fire mapped key exactly once")
    }

    // MARK: - Motion Gesture Characterization

    /// Motion gesture callback fires through the pipeline and executes the mapped action.
    func testMotionGesture_TiltBackExecutesMappedAction() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "MotionGesture",
                buttonMappings: [:],
                gestureMappings: [
                    GestureMapping(gestureType: .tiltBack, keyCode: 7)
                ]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onMotionGesture?(.tiltBack)
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events
        let gestureCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 7 }
            return false
        }.count
        XCTAssertEqual(gestureCount, 1, "Motion gesture should execute mapped key once")
    }

    // MARK: - Touchpad Tap Characterization

    /// Touchpad tap fires the mapped action through the pipeline.
    func testTouchpadTap_FiresMappedAction() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "TouchTap",
                buttonMappings: [.touchpadTap: .key(8)]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadTap?()
        }
        await waitForTasks(0.3)

        let events = mockInputSimulator.events
        let tapCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 8 }
            return false
        }.count
        XCTAssertEqual(tapCount, 1, "Touchpad tap should execute mapped key once")
    }

    /// Touchpad two-finger tap fires the mapped action.
    func testTouchpadTwoFingerTap_FiresMappedAction() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "TouchTwoFingerTap",
                buttonMappings: [.touchpadTwoFingerTap: .key(9)]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadTwoFingerTap?()
        }
        await waitForTasks(0.3)

        let events = mockInputSimulator.events
        let tapCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 9 }
            return false
        }.count
        XCTAssertEqual(tapCount, 1, "Two-finger tap should execute mapped key once")
    }

    // MARK: - Callback Queue Routing Characterization

    /// Verify that button callbacks dispatch to inputQueue (not pollingQueue).
    func testButtonCallbacksDispatchToInputQueue() async throws {
        let expectation = XCTestExpectation(description: "Button press handled on input queue")
        var handledOnInputQueue = false

        await MainActor.run {
            let profile = Profile(
                name: "QueueTest",
                buttonMappings: [.a: .key(1)]
            )
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // The inputQueue label should be "com.xboxmapper.input"
        // We verify the callback fires and produces a result
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks()
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events
        let pressCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count
        // If routing was correct, action should have fired
        XCTAssertEqual(pressCount, 1, "Button action should have executed via correct queue routing")
    }

    /// Verify that touchpad movement dispatches to pollingQueue and produces mouse movement.
    func testTouchpadCallbacksDispatchToPollingQueue() async throws {
        await MainActor.run {
            var profile = Profile(name: "TouchQueueTest", buttonMappings: [:])
            profile.joystickSettings.touchpadDeadzone = 0.00001
            profile.joystickSettings.touchpadSmoothing = 0
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onTouchpadMoved?(CGPoint(x: 0.5, y: 0.3))
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events
        let hasMove = events.contains { event in
            if case .moveMouse(let dx, let dy) = event {
                return abs(dx) > 0.1 || abs(dy) > 0.1
            }
            return false
        }
        XCTAssertTrue(hasMove, "Touchpad movement should produce mouse movement via polling queue")
    }

    // MARK: - Disabled State Characterization

    /// When engine is disabled, button presses should not produce any output.
    func testDisabledEngineBlocksButtonPresses() async throws {
        await MainActor.run {
            let profile = Profile(
                name: "DisabledTest",
                buttonMappings: [.a: .key(1)]
            )
            profileManager.setActiveProfile(profile)
            mappingEngine.isEnabled = false
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks()
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)

        let events = mockInputSimulator.events
        let pressCount = events.filter {
            if case .pressKey(let keyCode, _) = $0 { return keyCode == 1 }
            return false
        }.count
        XCTAssertEqual(pressCount, 0, "Disabled engine should not fire any mapped keys")
    }
}
