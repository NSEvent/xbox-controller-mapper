import XCTest
import Combine
import CoreGraphics
@testable import XboxControllerMapper

@MainActor
final class XboxControllerMapperTests: XCTestCase {
    
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    
    override func setUp() async throws {
        // Since ControllerService, ProfileManager, AppMonitor interact with system/files,
        // we should ideally mock them too, but for now we might be able to use real ones
        // if we are careful.
        // ProfileManager tries to read/write files. We should point it to a temp dir?
        // It uses FileManager.default.
        
        // For this test, we can use the real ControllerService as it just manages state and callbacks.
        // We can manually trigger callbacks.
        controllerService = ControllerService()
        
        // ProfileManager reads from disk. We'll let it read default or empty.
        // We will manually inject a profile anyway.
        profileManager = ProfileManager()
        
        // AppMonitor uses NSWorkspace. It might be flaky in CI but locally should be ok.
        appMonitor = AppMonitor()
        
        mockInputSimulator = MockInputSimulator()
        
        mappingEngine = MappingEngine(
            controllerService: controllerService,
            profileManager: profileManager,
            appMonitor: appMonitor,
            inputSimulator: mockInputSimulator
        )
        
        // Ensure engine is enabled
        mappingEngine.enable()
    }
    
    func testModifierCombinationMapping() throws {
        // Setup: Create a profile with specific mappings
        // LB -> Hold Command + Shift
        // A -> Key 'S'
        
        let lbMapping = KeyMapping(
            modifiers: ModifierFlags(command: true, shift: true),
            isHoldModifier: true
        )
        
        // KeyCode 1 is 'S'
        let aMapping = KeyMapping(keyCode: 1)
        
        let profile = Profile(
            name: "Test Profile",
            buttonMappings: [
                .leftBumper: lbMapping,
                .a: aMapping
            ]
        )
        
        profileManager.setActiveProfile(profile)
        
        // 1. Press Left Bumper
        // We need to simulate this via controllerService
        // controllerService.onButtonPressed is set by MappingEngine.
        // But MappingEngine sets it in init.
        // We can't easily invoke the closure that MappingEngine set because it's private.
        // But we can invoke the closure on ControllerService if we can access it.
        // Wait, ControllerService exposes `onButtonPressed` as a public var.
        // So MappingEngine SETS it.
        // So `controllerService.onButtonPressed` IS the closure MappingEngine provided.
        
        guard let onButtonPressed = controllerService.onButtonPressed else {
            XCTFail("MappingEngine didn't set onButtonPressed")
            return
        }
        
        guard let onButtonReleased = controllerService.onButtonReleased else {
            XCTFail("MappingEngine didn't set onButtonReleased")
            return
        }
        
        // Simulate LB Press
        onButtonPressed(.leftBumper)
        
        // Verify LB hold started
        // Depending on async nature, we might need to wait.
        // handleButtonPressed is wrapped in Task { @MainActor ... }
        
        // We need to wait for the Task to run.
        let expectation1 = XCTestExpectation(description: "LB Pressed processed")
        DispatchQueue.main.async {
            expectation1.fulfill()
        }
        wait(for: [expectation1], timeout: 1.0)
        
        XCTAssertTrue(mockInputSimulator.events.contains { event in
            if case .startHoldMapping(let mapping) = event {
                return mapping.isHoldModifier && mapping.modifiers.command && mapping.modifiers.shift
            }
            return false
        }, "Should have started holding modifiers")
        
        mockInputSimulator.events.removeAll()
        
        // 2. Press A
        onButtonPressed(.a)
        
        let expectation2 = XCTestExpectation(description: "A Pressed processed")
        DispatchQueue.main.async {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 1.0)
        
        // 3. Release A (Trigger mapping usually happens on release for standard keys in this engine?
        // Let's check MappingEngine.handleButtonPressed vs handleButtonReleased.
        // handleButtonPressed checks for hold modifier. If not, it sets up long hold timer.
        // handleButtonReleased cancels timer and executes if not double tap.
        // So 'A' press does nothing immediately (waits for release or long hold).
        
        onButtonReleased(.a, 0.1) // Short press
        
        let expectation3 = XCTestExpectation(description: "A Released processed")
        DispatchQueue.main.async {
            expectation3.fulfill()
        }
        wait(for: [expectation3], timeout: 1.0)
        
        // Verify 'S' was pressed.
        // The issue is: does it pick up the HELD modifiers from LB?
        // MappingEngine calls `inputSimulator.executeMapping(mapping)`
        // `mapping` for A is just key 'S' (no modifiers in mapping itself).
        // `InputSimulator.executeMapping` calls `pressKey(keyCode, modifiers: mapping.modifiers)`
        // `InputSimulator.pressKey` calculates `modifiersToPress = modifiers.subtracting(heldModifiers)`.
        // Then it posts event with `currentFlags = heldModifiers`.
        
        // In our Mock, `executeMapping` is called with the mapping from the profile.
        // The mapping for A has NO modifiers.
        // So `executeMapping` is called with 'S', no mods.
        
        // BUT, the REAL InputSimulator would then combine that with `heldModifiers`.
        // Our MockInputSimulator stores `executeMapping(KeyMapping)`.
        // It does NOT simulate the logic inside `InputSimulator.executeMapping` which combines modifiers.
        
        // To verify the bug/fix, we need to know what MappingEngine EXPECTS InputSimulator to do.
        // If MappingEngine relies on InputSimulator to maintain state, then `executeMapping` passing a mapping without modifiers is correct BEHAVIOR for MappingEngine, assuming InputSimulator handles the merge.
        
        // The user says: "pressing them together doesn't trigger the shortcut that I expect."
        // If the real app fails, it means either:
        // A) MappingEngine isn't sending the held modifiers (it shouldn't need to if InputSimulator tracks them).
        // B) InputSimulator isn't tracking them correctly.
        // C) InputSimulator isn't merging them correctly.
        
        // If I use a MockInputSimulator that just records `executeMapping`, I confirm that MappingEngine is sending "S" with no modifiers.
        // This is EXPECTED behavior for MappingEngine.
        
        // If I want to test the SYSTEM, I should perhaps use a smarter Mock that replicates InputSimulator's logic, OR test InputSimulator logic separately.
        
        // The user says "right now ... it doesn't trigger".
        // This implies the bug is likely in `InputSimulator.pressKey` or `MappingEngine`'s assumption.
        
        // Let's look at `InputSimulator.pressKey` logic again (simulated mentally).
        // `func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = [])`
        // `let modifiersToPress = modifiers.subtracting(heldModifiers)`
        // `var currentFlags = heldModifiers`
        // ... press new modifiers ...
        // `postKeyEvent(..., flags: currentFlags)`
        
        // If `modifiers` passed to `pressKey` is EMPTY (because A mapping has no modifiers),
        // `modifiersToPress` is empty.
        // `currentFlags` is `heldModifiers` (which should contain Cmd+Shift from LB).
        // `postKeyEvent` uses `currentFlags`.
        // So it sends 'S' with Cmd+Shift.
        
        // This LOOKS correct. Why does the user say it fails?
        // Maybe `MappingEngine` is NOT tracking `heldButtons` correctly or `InputSimulator` state is lost?
        
        // Or maybe `MappingEngine` passes the mapping to `executeMapping`, which calls `pressKey`.
        // If `MappingEngine` calls `executeMapping` with the A mapping (S, no mods).
        // `InputSimulator` uses its internal `heldModifiers`.
        
        // WAIT. `heldModifiers` in InputSimulator.
        // `MappingEngine` calls `startHoldMapping` for LB.
        // `InputSimulator.startHoldMapping` -> `holdModifier`.
        // `holdModifier` -> inserts into `heldModifiers`.
        
        // This seems correct.
        
        // Let's assume the user is correct and there is a bug.
        // Maybe I should write a test that FAILS if the logic is what I think it is?
        // No, I should write a test that verifies the expected behavior.
        
        // Test expectation: 'S' should be pressed with Cmd+Shift.
        // Since my Mock records `executeMapping`, I can't verify the final CGEvent.
        // But I can verify that `heldModifiers` in the mock are correct when `executeMapping` is called.
        
        XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held")
        XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift), "Shift should be held")
        
        // And I can verify that executeMapping was called with 'S'.
        XCTAssertTrue(mockInputSimulator.events.contains { event in
            if case .executeMapping(let mapping) = event {
                return mapping.keyCode == 1
            }
            return false
        })
    }
}
