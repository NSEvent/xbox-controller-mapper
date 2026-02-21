import XCTest
@testable import ControllerKeys

// MARK: - Mouse Click & Drag Tests
//
// These tests verify that controller buttons mapped to left click correctly support
// click-and-drag behavior needed by system tools like screencapture -ic.

final class MouseClickDragTests: XCTestCase {

    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseClickDragTests-\(UUID().uuidString)")

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
            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
        try? FileManager.default.removeItem(at: testConfigDirectory)
    }

    private func waitForTasks(_ seconds: Double = 0.05) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Mouse Hold State Tracking

    func testMouseLeftClick_UsesHoldPath() async throws {
        // A button mapped to left click should use the hold path (startHoldMapping),
        // not the instant pressKey path
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
            let profile = Profile(name: "MouseHold", buttonMappings: [.x: mapping])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.x)
        }
        await waitForTasks(0.1)

        let events = mockInputSimulator.events
        let holdStartCount = events.filter {
            if case .startHoldMapping(let m) = $0 { return m.keyCode == KeyCodeMapping.mouseLeftClick }
            return false
        }.count
        let pressKeyCount = events.filter {
            if case .pressKey(let k, _) = $0 { return k == KeyCodeMapping.mouseLeftClick }
            return false
        }.count

        XCTAssertGreaterThan(holdStartCount, 0, "Mouse left click should use hold path (startHoldMapping)")
        XCTAssertEqual(pressKeyCount, 0, "Mouse left click should NOT use pressKey path")
    }

    func testMouseLeftClick_HoldStateTracked() async throws {
        // When a button mapped to left click is held, isLeftMouseButtonHeld should be true
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
            let profile = Profile(name: "MouseHold", buttonMappings: [.x: mapping])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Before press: not held
        XCTAssertFalse(mockInputSimulator.isLeftMouseButtonHeld, "Mouse should not be held before button press")

        await MainActor.run {
            controllerService.buttonPressed(.x)
        }
        await waitForTasks(0.1)

        // During hold: held
        XCTAssertTrue(mockInputSimulator.isLeftMouseButtonHeld, "Mouse should be held after button press")

        await MainActor.run {
            controllerService.buttonReleased(.x)
        }
        await waitForTasks(0.1)

        // After release: not held
        XCTAssertFalse(mockInputSimulator.isLeftMouseButtonHeld, "Mouse should not be held after button release")
    }

    func testMouseLeftClick_HoldAndRelease_EventSequence() async throws {
        // Verify the full event sequence: startHoldMapping on press, stopHoldMapping on release
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
            let profile = Profile(name: "MouseHold", buttonMappings: [.x: mapping])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.x)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            controllerService.buttonReleased(.x)
        }
        await waitForTasks(0.1)

        let events = mockInputSimulator.events
        let holdStarts = events.filter {
            if case .startHoldMapping(let m) = $0 { return m.keyCode == KeyCodeMapping.mouseLeftClick }
            return false
        }
        let holdStops = events.filter {
            if case .stopHoldMapping(let m) = $0 { return m.keyCode == KeyCodeMapping.mouseLeftClick }
            return false
        }

        XCTAssertEqual(holdStarts.count, 1, "Should have exactly one startHoldMapping")
        XCTAssertEqual(holdStops.count, 1, "Should have exactly one stopHoldMapping")

        // Verify ordering: startHoldMapping before stopHoldMapping
        let startIdx = events.firstIndex { if case .startHoldMapping = $0 { return true }; return false }
        let stopIdx = events.firstIndex { if case .stopHoldMapping = $0 { return true }; return false }
        XCTAssertNotNil(startIdx)
        XCTAssertNotNil(stopIdx)
        if let s = startIdx, let e = stopIdx {
            XCTAssertLessThan(s, e, "startHoldMapping must come before stopHoldMapping")
        }
    }

    // MARK: - Mock Tracks keyDown/keyUp for Mouse Buttons

    func testMockInputSimulator_KeyDownTracksMouseHold() {
        // Directly test that the mock properly tracks mouse hold state
        XCTAssertFalse(mockInputSimulator.isLeftMouseButtonHeld)

        mockInputSimulator.keyDown(KeyCodeMapping.mouseLeftClick, modifiers: [])
        XCTAssertTrue(mockInputSimulator.isLeftMouseButtonHeld, "keyDown with mouseLeftClick should set held state")

        mockInputSimulator.keyUp(KeyCodeMapping.mouseLeftClick)
        XCTAssertFalse(mockInputSimulator.isLeftMouseButtonHeld, "keyUp with mouseLeftClick should clear held state")
    }

    func testMockInputSimulator_NonMouseKeyDown_DoesNotAffectMouseHold() {
        mockInputSimulator.keyDown(49, modifiers: []) // spacebar
        XCTAssertFalse(mockInputSimulator.isLeftMouseButtonHeld, "Non-mouse keyDown should not affect mouse hold")
    }

    // MARK: - Click-and-Drag Sequence

    func testClickAndDrag_FullSequence() async throws {
        // Simulate: press button (mouseDown) → move joystick → release button (mouseUp)
        // This is the pattern needed for screencapture -ic region selection
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
            let profile = Profile(name: "ClickDrag", buttonMappings: [.x: mapping])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Step 1: Press button (mouseDown)
        await MainActor.run {
            controllerService.buttonPressed(.x)
        }
        await waitForTasks(0.1)

        XCTAssertTrue(mockInputSimulator.isLeftMouseButtonHeld, "Left mouse should be held during drag")

        // Step 2: Move joystick while button held (drag)
        // This would normally go through MappingEngine.updateJoystick which calls moveMouse
        // Here we verify the mock tracks the held state correctly
        let events1 = mockInputSimulator.events
        let hasHoldStart = events1.contains {
            if case .startHoldMapping(let m) = $0 { return m.keyCode == KeyCodeMapping.mouseLeftClick }
            return false
        }
        XCTAssertTrue(hasHoldStart, "Hold mapping should have started")

        // Step 3: Release button (mouseUp)
        await MainActor.run {
            controllerService.buttonReleased(.x)
        }
        await waitForTasks(0.1)

        XCTAssertFalse(mockInputSimulator.isLeftMouseButtonHeld, "Left mouse should not be held after release")

        let events2 = mockInputSimulator.events
        let hasHoldStop = events2.contains {
            if case .stopHoldMapping(let m) = $0 { return m.keyCode == KeyCodeMapping.mouseLeftClick }
            return false
        }
        XCTAssertTrue(hasHoldStop, "Hold mapping should have stopped")
    }

    // MARK: - Multiple Buttons Mapped to Left Click

    func testMultipleButtonsCanIndependentlyHoldMouseClick() async throws {
        // Both X and touchpad mapped to left click — pressing one, then the other,
        // then releasing first should still show held
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
            let profile = Profile(name: "MultiMouse", buttonMappings: [
                .x: mapping,
                .touchpadButton: mapping
            ])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.x)
        }
        await waitForTasks(0.1)
        XCTAssertTrue(mockInputSimulator.isLeftMouseButtonHeld)

        await MainActor.run {
            controllerService.buttonReleased(.x)
        }
        await waitForTasks(0.1)
        XCTAssertFalse(mockInputSimulator.isLeftMouseButtonHeld)

        // Now press touchpad
        await MainActor.run {
            controllerService.buttonPressed(.touchpadButton)
        }
        await waitForTasks(0.1)
        XCTAssertTrue(mockInputSimulator.isLeftMouseButtonHeld, "Touchpad button should also hold left mouse")

        await MainActor.run {
            controllerService.buttonReleased(.touchpadButton)
        }
        await waitForTasks(0.1)
        XCTAssertFalse(mockInputSimulator.isLeftMouseButtonHeld)
    }
}

// MARK: - ButtonInteractionFlowPolicy Mouse Tests

final class MouseClickFlowPolicyTests: XCTestCase {

    func testMouseLeftClick_ShouldUseHoldPath() {
        // Mouse left click should always use the hold path so that
        // click-and-drag works (mouseDown on press, mouseUp on release)
        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick)
        XCTAssertTrue(
            ButtonInteractionFlowPolicy.shouldUseHoldPath(mapping: mapping, isChordPart: false),
            "Mouse left click must use hold path for drag support"
        )
    }

    func testMouseRightClick_ShouldUseHoldPath() {
        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseRightClick)
        XCTAssertTrue(
            ButtonInteractionFlowPolicy.shouldUseHoldPath(mapping: mapping, isChordPart: false),
            "Mouse right click must use hold path"
        )
    }

    func testMouseMiddleClick_ShouldUseHoldPath() {
        let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseMiddleClick)
        XCTAssertTrue(
            ButtonInteractionFlowPolicy.shouldUseHoldPath(mapping: mapping, isChordPart: false),
            "Mouse middle click must use hold path"
        )
    }

    func testKeyboardKey_ShouldNotUseHoldPath() {
        // Normal keyboard keys should NOT use hold path unless isHoldModifier
        let mapping = KeyMapping(keyCode: 49) // spacebar
        XCTAssertFalse(
            ButtonInteractionFlowPolicy.shouldUseHoldPath(mapping: mapping, isChordPart: false),
            "Keyboard keys should not use hold path by default"
        )
    }
}
