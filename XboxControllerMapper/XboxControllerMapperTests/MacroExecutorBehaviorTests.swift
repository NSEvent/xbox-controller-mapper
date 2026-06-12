import XCTest
import CoreGraphics
import Carbon.HIToolbox
@testable import ControllerKeys

/// Pins MacroExecutor's per-step contract with InputSimulatorProtocol and
/// SystemCommandExecutor ahead of the TriggerKit execution-layer refactor.
///
/// MacroEngineTests covers macros end-to-end through MappingEngine; these
/// tests exercise MacroExecutor directly so the exact seam being rewired
/// (step -> simulator/system-command call sequences) has its own coverage.
@MainActor
final class MacroExecutorBehaviorTests: XCTestCase {

    private final class SpySystemCommandExecutor: SystemCommandExecutor, @unchecked Sendable {
        private let lock = NSLock()
        private var _commands: [SystemCommand] = []

        var commands: [SystemCommand] {
            lock.lock()
            defer { lock.unlock() }
            return _commands
        }

        override func execute(_ command: SystemCommand) {
            lock.lock()
            _commands.append(command)
            lock.unlock()
        }
    }

    private var mockInputSimulator: MockInputSimulator!
    private var spySystemCommandExecutor: SpySystemCommandExecutor!
    private var executor: MacroExecutor!
    private var profileManager: ProfileManager!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)
        profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
        mockInputSimulator = MockInputSimulator()
        spySystemCommandExecutor = SpySystemCommandExecutor(profileManager: profileManager)
        executor = MacroExecutor(
            inputSimulator: mockInputSimulator,
            systemCommandExecutor: spySystemCommandExecutor
        )
    }

    override func tearDown() async throws {
        executor = nil
        spySystemCommandExecutor = nil
        mockInputSimulator = nil
        profileManager = nil
        if let testConfigDirectory {
            try? FileManager.default.removeItem(at: testConfigDirectory)
        }
        testConfigDirectory = nil
        try await super.tearDown()
    }

    /// Polls until `condition` is true or the timeout elapses. Macro execution is
    /// asynchronous (detached task today, executor hop after the refactor), so
    /// assertions wait on observable effects rather than implementation details.
    private func waitUntil(
        timeout: TimeInterval = 3.0,
        _ condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    // MARK: - Key press steps

    func testPressStepWithModifiersPostsSinglePressKey() async {
        let macro = Macro(name: "Press", steps: [
            .press(KeyMapping(keyCode: 0, modifiers: .command))
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 1 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        XCTAssertEqual(mockInputSimulator.events, [.pressKey(0, .maskCommand)])
    }

    func testMultiplePressStepsPreserveOrder() async {
        let macro = Macro(name: "Sequence", steps: [
            .press(KeyMapping(keyCode: 0)),
            .press(KeyMapping(keyCode: 1)),
            .press(KeyMapping(keyCode: 2))
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 3 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        XCTAssertEqual(mockInputSimulator.events, [
            .pressKey(0, []),
            .pressKey(1, []),
            .pressKey(2, [])
        ])
    }

    func testModifierOnlyPressHoldsThenReleasesEachModifier() async {
        let macro = Macro(name: "ModifierOnly", steps: [
            .press(KeyMapping(modifiers: ModifierFlags(command: true, shift: true)))
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 4 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        // Press order is command, shift (ModifierKeyState.modifierPressOrder);
        // release happens in reverse. No plain key event should be posted.
        XCTAssertEqual(mockInputSimulator.events, [
            .holdModifier(.maskCommand),
            .holdModifier(.maskShift),
            .releaseModifier(.maskShift),
            .releaseModifier(.maskCommand)
        ])
    }

    // MARK: - Hold steps

    func testHoldStepSequencesModifiersAroundKey() async {
        let start = Date()
        let macro = Macro(name: "Hold", steps: [
            .hold(KeyMapping(keyCode: 4, modifiers: .command), duration: 0.15)
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 4 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        XCTAssertEqual(mockInputSimulator.events, [
            .holdModifier(.maskCommand),
            .keyDown(4),
            .keyUp(4),
            .releaseModifier(.maskCommand)
        ])
        XCTAssertGreaterThanOrEqual(
            Date().timeIntervalSince(start), 0.1,
            "Hold step should keep the key down for roughly the requested duration"
        )
    }

    func testHoldStepWithModifierKeyUsesModifierHold() async {
        let macro = Macro(name: "HoldModifierKey", steps: [
            .hold(KeyMapping(keyCode: CGKeyCode(kVK_Command)), duration: 0.05)
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 2 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        // Modifier key codes route through holdModifierKey/releaseModifierKey,
        // not plain keyDown/keyUp, so the OS sees a real modifier press.
        XCTAssertEqual(mockInputSimulator.events, [
            .holdModifier(.maskCommand),
            .releaseModifier(.maskCommand)
        ])
    }

    func testModifierOnlyHoldHoldsForDuration() async {
        let macro = Macro(name: "ModifierOnlyHold", steps: [
            .hold(KeyMapping(modifiers: .option), duration: 0.05)
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 2 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        XCTAssertEqual(mockInputSimulator.events, [
            .holdModifier(.maskAlternate),
            .releaseModifier(.maskAlternate)
        ])
    }

    // MARK: - Delay steps

    func testDelayStepSeparatesPressesAndPreservesOrder() async {
        let start = Date()
        let macro = Macro(name: "Delayed", steps: [
            .press(KeyMapping(keyCode: 0)),
            .delay(0.15),
            .press(KeyMapping(keyCode: 1))
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 2 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        XCTAssertEqual(mockInputSimulator.events, [
            .pressKey(0, []),
            .pressKey(1, [])
        ])
        XCTAssertGreaterThanOrEqual(
            Date().timeIntervalSince(start), 0.1,
            "Delay step should actually wait before the next step"
        )
    }

    func testNegativeDelayAndHoldDurationsDoNotCrashOrStall() async {
        let macro = Macro(name: "Negative", steps: [
            .delay(-5),
            .hold(KeyMapping(keyCode: 0), duration: -1),
            .press(KeyMapping(keyCode: 1))
        ])

        executor.execute(macro)

        let completed = await waitUntil {
            self.mockInputSimulator.events.contains(.pressKey(1, []))
        }
        XCTAssertTrue(completed, "Negative durations should clamp to zero, not crash or stall")
    }

    // MARK: - Type text steps

    func testTypeTextStepForwardsParameters() async {
        let macro = Macro(name: "Type", steps: [
            .typeText("hi there", speed: 240, pressEnter: true)
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 1 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        XCTAssertEqual(mockInputSimulator.events, [.typeText("hi there", 240, true)])
    }

    func testTypeTextPasteSpeedZeroForwardsZero() async {
        let macro = Macro(name: "Paste", steps: [
            .typeText("clipboard text", speed: 0, pressEnter: false)
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 1 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        XCTAssertEqual(mockInputSimulator.events, [.typeText("clipboard text", 0, false)])
    }

    // MARK: - Synthetic marker key codes

    func testMouseMarkerPressRoutesThroughPressKey() async {
        let macro = Macro(name: "Click", steps: [
            .press(KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick))
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 1 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        // Mouse marker codes flow through pressKey, where the real simulator
        // dispatches them to its mouse-click path.
        XCTAssertEqual(mockInputSimulator.events, [.pressKey(KeyCodeMapping.mouseLeftClick, [])])
    }

    func testMediaKeyMarkerPressRoutesThroughPressKey() async {
        let macro = Macro(name: "PlayPause", steps: [
            .press(KeyMapping(keyCode: KeyCodeMapping.mediaPlayPause))
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.mockInputSimulator.events.count >= 1 }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        XCTAssertEqual(mockInputSimulator.events, [.pressKey(KeyCodeMapping.mediaPlayPause, [])])
    }

    // MARK: - System command steps

    func testShellWebhookAndOBSStepsDispatchToSystemCommandExecutor() async {
        let macro = Macro(name: "SystemSteps", steps: [
            .shellCommand(command: "echo hi", inTerminal: false),
            .webhook(url: "https://example.com/hook", method: .POST, headers: ["X-A": "1"], body: "{}"),
            .obsWebSocket(url: "ws://localhost:4455", password: nil, requestType: "ToggleRecord", requestData: nil)
        ])

        executor.execute(macro)

        let completed = await waitUntil { self.spySystemCommandExecutor.commands.count >= 3 }
        XCTAssertTrue(completed, "Macro should dispatch all system command steps")
        XCTAssertEqual(spySystemCommandExecutor.commands, [
            .shellCommand(command: "echo hi", inTerminal: false),
            .httpRequest(url: "https://example.com/hook", method: .POST, headers: ["X-A": "1"], body: "{}"),
            .obsWebSocket(url: "ws://localhost:4455", password: nil, requestType: "ToggleRecord", requestData: nil)
        ])
        XCTAssertTrue(mockInputSimulator.events.isEmpty, "System command steps should not touch the input simulator")
    }

    // MARK: - Mixed sequences

    func testMixedStepKindsExecuteInOrder() async {
        let macro = Macro(name: "Mixed", steps: [
            .press(KeyMapping(keyCode: 0)),
            .shellCommand(command: "true", inTerminal: false),
            .press(KeyMapping(keyCode: 1))
        ])

        executor.execute(macro)

        let completed = await waitUntil {
            self.mockInputSimulator.events.count >= 2 && self.spySystemCommandExecutor.commands.count >= 1
        }
        XCTAssertTrue(completed, "Macro should execute within timeout")
        XCTAssertEqual(mockInputSimulator.events, [.pressKey(0, []), .pressKey(1, [])])
        XCTAssertEqual(spySystemCommandExecutor.commands, [.shellCommand(command: "true", inTerminal: false)])
    }

    func testEmptyMacroProducesNoEffects() async {
        executor.execute(Macro(name: "Empty", steps: []))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(mockInputSimulator.events.isEmpty)
        XCTAssertTrue(spySystemCommandExecutor.commands.isEmpty)
    }
}
