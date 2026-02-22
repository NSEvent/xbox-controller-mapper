import XCTest
import CoreGraphics
@testable import ControllerKeys

// MARK: - Action Priority Dispatch Characterization Tests
//
// These tests capture the current behavior of MappingExecutor's action dispatch chain:
//   systemCommand > macro > script > keyPress
//
// They use MockInputSimulator (from XboxControllerMapperTests.swift) and real
// MappingExecutor wiring to verify the priority ordering is preserved after refactoring.

final class ActionPriorityDispatchTests: XCTestCase {

    private var mockInputSimulator: MockInputSimulator!
    private var profileManager: ProfileManager!
    private var executor: MappingExecutor!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-action-dispatch-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            mockInputSimulator = MockInputSimulator()
            profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
            executor = MappingExecutor(
                inputSimulator: mockInputSimulator,
                inputQueue: DispatchQueue(label: "test.input", qos: .userInteractive),
                inputLogService: nil,
                profileManager: profileManager
            )
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            mockInputSimulator = nil
            profileManager = nil
            executor = nil
        }
        if let dir = testConfigDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Priority: systemCommand wins over everything

    func testSystemCommandTakesPriorityOverMacro() async {
        // A mapping with both systemCommand and macroId set — systemCommand should win
        let action = KeyMapping(
            macroId: UUID(),
            systemCommand: .openLink(url: "https://example.com")
        )
        let profile = Profile(name: "Test")

        let feedback = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        // systemCommand fires — feedback should contain the link display name
        XCTAssertTrue(feedback.contains("example.com") || feedback.contains("Open"),
            "System command should win: got '\(feedback)'")

        // No key presses should have occurred (macro didn't fire)
        let events = mockInputSimulator.events
        let pressEvents = events.filter { if case .pressKey = $0 { return true }; return false }
        XCTAssertEqual(pressEvents.count, 0, "Macro should not fire when systemCommand is present")
    }

    // MARK: - Priority: macro wins over script and keyPress

    func testMacroTakesPriorityOverKeyPress() async {
        let macroId = UUID()
        let macro = Macro(id: macroId, name: "TestMacro", steps: [
            .press(KeyMapping(keyCode: 42))
        ])
        let action = KeyMapping(
            keyCode: 99,  // This keyPress should NOT fire
            macroId: macroId
        )
        let profile = Profile(name: "Test", macros: [macro])

        let feedback = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        XCTAssertEqual(feedback, "TestMacro", "Macro name should be returned as feedback")

        // Wait for async macro execution on MacroExecutor's queue
        try? await Task.sleep(nanoseconds: 200_000_000)

        // The macro's key (42) should fire, not the mapping's key (99)
        let events = mockInputSimulator.events
        let macroKeyFired = events.contains { if case .pressKey(42, _) = $0 { return true }; return false }
        let directKeyFired = events.contains { if case .pressKey(99, _) = $0 { return true }; return false }
        XCTAssertTrue(macroKeyFired, "Macro step key should fire")
        XCTAssertFalse(directKeyFired, "Direct keyCode should not fire when macro is present")
    }

    // MARK: - Priority: keyPress is the fallback

    func testKeyPressFallback() async {
        let action = KeyMapping(keyCode: 49, modifiers: .command)  // Cmd+Space
        let profile = Profile(name: "Test")

        let feedback = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        XCTAssertTrue(feedback.contains("⌘"), "Feedback should show command modifier")

        let events = mockInputSimulator.events
        let pressEvent = events.first { if case .pressKey(49, _) = $0 { return true }; return false }
        XCTAssertNotNil(pressEvent, "Key press should fire as fallback")
    }

    // MARK: - Modifier-only mapping (tap)

    func testModifierOnlyMappingTaps() async {
        let action = KeyMapping(modifiers: .shift)
        let profile = Profile(name: "Test")

        let _ = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        // Should hold and then release the modifier
        let events = mockInputSimulator.events
        let holdEvents = events.filter { if case .holdModifier = $0 { return true }; return false }
        XCTAssertGreaterThan(holdEvents.count, 0, "Modifier should be held for tap")
    }

    // MARK: - Empty action does nothing

    func testEmptyActionProducesNoEvents() async {
        let action = KeyMapping()
        let profile = Profile(name: "Test")

        let feedback = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        XCTAssertEqual(feedback, "None", "Empty mapping feedback should be 'None'")
        XCTAssertTrue(mockInputSimulator.events.isEmpty, "No events for empty mapping")
    }
}

// MARK: - MacroActionHandler Isolation Tests

final class MacroActionHandlerIsolationTests: XCTestCase {

    private var mockInputSimulator: MockInputSimulator!
    private var profileManager: ProfileManager!
    private var executor: MappingExecutor!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-macro-isolation-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            mockInputSimulator = MockInputSimulator()
            profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
            executor = MappingExecutor(
                inputSimulator: mockInputSimulator,
                inputQueue: DispatchQueue(label: "test.input", qos: .userInteractive),
                inputLogService: nil,
                profileManager: profileManager
            )
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            mockInputSimulator = nil
            profileManager = nil
            executor = nil
        }
        if let dir = testConfigDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func testMacroWithMultipleSteps() async {
        let macroId = UUID()
        let macro = Macro(id: macroId, name: "MultiStep", steps: [
            .press(KeyMapping(keyCode: 1)),
            .press(KeyMapping(keyCode: 2)),
            .press(KeyMapping(keyCode: 3))
        ])
        let action = KeyMapping(macroId: macroId)
        let profile = Profile(name: "Test", macros: [macro])

        let _ = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        // Wait for async macro execution on keyboardQueue
        try? await Task.sleep(nanoseconds: 200_000_000)

        let events = mockInputSimulator.events
        let keyPresses = events.compactMap { event -> CGKeyCode? in
            if case .pressKey(let code, _) = event { return code }
            return nil
        }
        XCTAssertEqual(keyPresses, [1, 2, 3], "Macro steps should execute in order")
    }

    func testMacroWithTypeText() async {
        let macroId = UUID()
        let macro = Macro(id: macroId, name: "TypeTest", steps: [
            .typeText("hello", speed: 0, pressEnter: true)
        ])
        let action = KeyMapping(macroId: macroId)
        let profile = Profile(name: "Test", macros: [macro])

        let _ = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        // Wait for async macro execution
        try? await Task.sleep(nanoseconds: 200_000_000)

        let events = mockInputSimulator.events
        let typeEvents = events.filter { if case .typeText = $0 { return true }; return false }
        XCTAssertGreaterThan(typeEvents.count, 0, "Type text step should fire")
    }

    func testMacroNotFoundReturnsHintOrFallback() async {
        let missingMacroId = UUID()
        let action = KeyMapping(macroId: missingMacroId, hint: "Custom Hint")
        let profile = Profile(name: "Test", macros: [])

        let feedback = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        XCTAssertEqual(feedback, "Custom Hint", "Should return hint when macro not found")
    }

    func testMacroNotFoundWithoutHintReturnsFallback() async {
        let missingMacroId = UUID()
        let action = KeyMapping(macroId: missingMacroId)
        let profile = Profile(name: "Test", macros: [])

        let feedback = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        XCTAssertEqual(feedback, "Macro", "Should return 'Macro' fallback when macro not found and no hint")
    }
}

// MARK: - OnScreenKeyboard Integration Test

final class OnScreenKeyboardNotificationTests: XCTestCase {

    private var mockInputSimulator: MockInputSimulator!
    private var profileManager: ProfileManager!
    private var executor: MappingExecutor!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-osk-notify-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            mockInputSimulator = MockInputSimulator()
            profileManager = ProfileManager(configDirectoryOverride: testConfigDirectory)
            executor = MappingExecutor(
                inputSimulator: mockInputSimulator,
                inputQueue: DispatchQueue(label: "test.input", qos: .userInteractive),
                inputLogService: nil,
                profileManager: profileManager
            )
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            mockInputSimulator = nil
            profileManager = nil
            executor = nil
        }
        if let dir = testConfigDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Verifies that key presses through the executor still trigger
    /// OnScreenKeyboardManager.notifyControllerKeyPress
    func testKeyPressNotifiesOnScreenKeyboard() async {
        // This test verifies the call happens by checking that pressKey is called,
        // which is the prerequisite for the notification in KeyOrModifierActionHandler
        let action = KeyMapping(keyCode: 49)  // Space
        let profile = Profile(name: "Test")

        let _ = await MainActor.run {
            executor.executeAction(action, profile: profile)
        }

        let events = mockInputSimulator.events
        let spacePress = events.contains { if case .pressKey(49, _) = $0 { return true }; return false }
        XCTAssertTrue(spacePress, "Key press should fire through executor for OSK notification path")
    }
}
