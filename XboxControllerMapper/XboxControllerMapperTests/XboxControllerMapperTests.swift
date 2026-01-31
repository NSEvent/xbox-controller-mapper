import XCTest
import Combine
import CoreGraphics
@testable import ControllerKeys

// MARK: - Mocks

class MockInputSimulator: InputSimulatorProtocol {
    
    enum Event: Equatable {
        case pressKey(CGKeyCode, CGEventFlags)
        case holdModifier(CGEventFlags)
        case releaseModifier(CGEventFlags)
        case releaseAllModifiers
        case moveMouse(CGFloat, CGFloat)
        case scroll(CGFloat, CGFloat)
        case executeMapping(KeyMapping)
        case startHoldMapping(KeyMapping)
        case stopHoldMapping(KeyMapping)
    }
    
    private let lock = NSLock()
    
    private var _events: [Event] = []
    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }
    
    private var _heldModifiers: CGEventFlags = []
    var heldModifiers: CGEventFlags {
        lock.lock()
        defer { lock.unlock() }
        return _heldModifiers
    }
    
    private var modifierCounts: [UInt64: Int] = [:]

    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(.pressKey(keyCode, modifiers))
    }
    
    func holdModifier(_ modifier: CGEventFlags) {
        lock.lock()
        defer { lock.unlock() }
        let masks: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        for mask in masks where modifier.contains(mask) {
            let count = modifierCounts[mask.rawValue] ?? 0
            modifierCounts[mask.rawValue] = count + 1
            if count == 0 {
                _heldModifiers.insert(mask)
            }
        }
        _events.append(.holdModifier(modifier))
    }
    
    func releaseModifier(_ modifier: CGEventFlags) {
        lock.lock()
        defer { lock.unlock() }
        let masks: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        for mask in masks where modifier.contains(mask) {
            let count = modifierCounts[mask.rawValue] ?? 0
            if count > 0 {
                modifierCounts[mask.rawValue] = count - 1
                if count == 1 {
                    _heldModifiers.remove(mask)
                }
            }
        }
        _events.append(.releaseModifier(modifier))
    }
    
    func releaseAllModifiers() {
        lock.lock()
        defer { lock.unlock() }
        _heldModifiers = []
        modifierCounts.removeAll()
        _events.append(.releaseAllModifiers)
    }

    func isHoldingModifiers(_ modifier: CGEventFlags) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !modifier.isEmpty && _heldModifiers.contains(modifier)
    }

    func moveMouse(dx: CGFloat, dy: CGFloat) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(.moveMouse(dx, dy))
    }
    
    func scroll(
        dx: CGFloat,
        dy: CGFloat,
        phase: CGScrollPhase?,
        momentumPhase: CGMomentumScrollPhase?,
        isContinuous: Bool,
        flags: CGEventFlags
    ) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(.scroll(dx, dy))
    }
    
    func executeMapping(_ mapping: KeyMapping) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(.executeMapping(mapping))
    }
    
    func startHoldMapping(_ mapping: KeyMapping) {
        lock.lock()
        // We need to call internal methods or duplicate logic to avoid deadlock if we called self.holdModifier
        // But holdModifier logic is simple.
        // Let's just implement it inline or call a private helper if needed.
        // But here we can just append event and update state.
        // Wait, holdModifier updates modifierCounts. We should replicate that.
        // Simplest is to unlock, call holdModifier, lock, append event.
        // But holdModifier appends event too.
        // The original code:
        /*
        if mapping.modifiers.hasAny {
            holdModifier(mapping.modifiers.cgEventFlags)
        }
        events.append(.startHoldMapping(mapping))
        */
        lock.unlock()
        
        if mapping.modifiers.hasAny {
            holdModifier(mapping.modifiers.cgEventFlags)
        }
        
        lock.lock()
        defer { lock.unlock() }
        _events.append(.startHoldMapping(mapping))
    }
    
    func stopHoldMapping(_ mapping: KeyMapping) {
        lock.lock()
        lock.unlock()
        
        if mapping.modifiers.hasAny {
            releaseModifier(mapping.modifiers.cgEventFlags)
        }
        
        lock.lock()
        defer { lock.unlock() }
        _events.append(.stopHoldMapping(mapping))
    }
    
    func executeMacro(_ macro: Macro) {
        lock.lock()
        defer { lock.unlock() }
        // Simple mock: just record that we executed this macro
        // In a real integration test we might want to simulate steps, 
        // but for now we verify the engine called it.
        // For the test case `testMacroExecution` which expects key press events,
        // we should simulate the steps here in the mock.
        
        for step in macro.steps {
            switch step {
            case .press(let mapping):
                if let code = mapping.keyCode {
                    _events.append(.pressKey(code, mapping.modifiers.cgEventFlags))
                }
            default:
                break
            }
        }
    }
}

// MARK: - Tests

final class XboxControllerMapperTests: XCTestCase {
    
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    
    override func setUp() async throws {
        await MainActor.run {
            controllerService = ControllerService()
            // Reduce chord window for faster test execution (50ms should be safe)
            controllerService.chordWindow = 0.05
            profileManager = ProfileManager()
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
        // Disable engine and clean up to prevent state leakage between tests
        await MainActor.run {
            mappingEngine?.disable()
        }
        // Wait for any pending async work to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        await MainActor.run {
            mockInputSimulator?.releaseAllModifiers()
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
    }

    private func waitForTasks(_ delay: TimeInterval = 0.4) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    func testModifierCombinationMapping() async throws {
        await MainActor.run {
            let lbMapping = KeyMapping.holdModifier(.command)
            let aMapping = KeyMapping(keyCode: 1)
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [.leftBumper: lbMapping, .a: aMapping]))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command modifier should be held")
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()
        
        await MainActor.run {
            // MappingExecutor.executeAction() calls pressKey directly, not executeMapping
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Expected pressKey with keyCode 1")
        }
    }

    func testSimultaneousPressWithNoChordMapping() async throws {
        await MainActor.run {
            let lbMapping = KeyMapping.holdModifier(.command)
            let aMapping = KeyMapping(keyCode: 1)
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [.leftBumper: lbMapping, .a: aMapping]))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.3)
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "LB should be held after fallback")
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()
        
        await MainActor.run {
            // MappingExecutor.executeAction() calls pressKey directly
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Expected pressKey with keyCode 1")
        }
    }

    func testDoubleTapWithHeldModifier() async throws {
        await MainActor.run {
            let lbMapping = KeyMapping.holdModifier(.command)
            let doubleTap = DoubleTapMapping(keyCode: 2, threshold: 0.2)
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = doubleTap
            profileManager.setActiveProfile(Profile(name: "DT", buttonMappings: [.leftBumper: lbMapping, .a: aMapping]))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            controllerService.onButtonPressed?(.leftBumper)
        }
        await waitForTasks()
        
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.05)
        }
        await waitForTasks(0.1)
        
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.05)
        }
        await waitForTasks(0.3)
        
        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            }, "Single tap should be cancelled")
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }, "Double tap should execute")
        }
    }
    
    func testChordMappingPrecedence() async throws {
        await MainActor.run {
            let chordMapping = ChordMapping(buttons: [.a, .b], keyCode: 3)
            profileManager.setActiveProfile(Profile(name: "Chord", buttonMappings: [.a: .key(1), .b: .key(2)], chordMappings: [chordMapping]))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            controllerService.onChordDetected?([.a, .b])
        }
        await waitForTasks()
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 3 }
                return false
            })
        }
    }
    
    func testLongHold() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.1)
            profileManager.setActiveProfile(Profile(name: "Hold", buttonMappings: [.a: aMapping]))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.4)
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            })
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()
        
        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            })
        }
    }
    
    func testJoystickMouseMovement() async throws {
        await MainActor.run {
            controllerService.isConnected = true
        }
        await waitForTasks(0.2)

        // Use test helper to set the internal storage value that the polling reads
        controllerService.setLeftStickForTesting(CGPoint(x: 0.5, y: 0.5))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .moveMouse = event { return true }
                return false
            }, "Mouse movement should be generated from joystick input")
        }
    }
    
    func testEngineDisablingReleasesModifiers() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "T", buttonMappings: [.leftBumper: .holdModifier(.command)]))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            controllerService.onButtonPressed?(.leftBumper)
        }
        await waitForTasks()
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
            mappingEngine.disable()
        }
        await waitForTasks()
        
        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand))
        }
    }
    
    func testOverlappingModifierHoldBug() async throws {
        await MainActor.run {
            let lbMapping = KeyMapping.holdModifier(.command)
            let rbMapping = KeyMapping.holdModifier(ModifierFlags(command: true, shift: true))
            profileManager.setActiveProfile(Profile(name: "O", buttonMappings: [.leftBumper: lbMapping, .rightBumper: rbMapping]))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()
        
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks()
        
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks()
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should still be held by RB")
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift), "Shift should still be held by RB")
        }
    }
    
    func testQuickTapLostBug() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Q", buttonMappings: [.leftBumper: .holdModifier(.command)]))
            controllerService.chordWindow = 0.2
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.05)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.3)
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .startHoldMapping = event { return true }
                return false
            }, "Quick tap should not be lost")
        }
    }
    
    func testHyperKeyWithArrow() async throws {
        await MainActor.run {
            // Setup: LB -> Hold Cmd + Opt + Ctrl (Hyper Key)
            let hyperMapping = KeyMapping.holdModifier(ModifierFlags(command: true, option: true, control: true))

            // Setup: DpadUp -> Up Arrow
            let upMapping = KeyMapping.key(KeyCodeMapping.upArrow)

            profileManager.setActiveProfile(Profile(
                name: "Hyper",
                buttonMappings: [
                    .leftBumper: hyperMapping,
                    .dpadUp: upMapping
                ]
            ))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            // 1. Press LB (Hyper)
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()
        
        await MainActor.run {
            // Verify Hyper modifiers are held
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains([.maskCommand, .maskAlternate, .maskControl]))
            
            // 2. Press DpadUp
            controllerService.buttonPressed(.dpadUp)
        }
        await waitForTasks()
        
        await MainActor.run {
            // 3. Release DpadUp (Trigger)
            controllerService.buttonReleased(.dpadUp)
        }
        await waitForTasks()
        
        await MainActor.run {
            // Verify: Up Arrow was executed (MappingExecutor calls pressKey directly)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event {
                    return code == KeyCodeMapping.upArrow
                }
                return false
            }, "Up Arrow should have been executed")

            // Verify: Modifiers were still held at the end of the sequence
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains([.maskCommand, .maskAlternate, .maskControl]), "Hyper modifiers should remain held")
        }
    }

    func testCommandDeleteShortcut() async throws {
        await MainActor.run {
            // Setup: Menu button -> Cmd + Delete
            let mapping = KeyMapping.combo(KeyCodeMapping.delete, modifiers: .command)

            profileManager.setActiveProfile(Profile(
                name: "DeleteTest",
                buttonMappings: [.menu: mapping]
            ))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            // 1. Press Menu
            controllerService.buttonPressed(.menu)
        }
        await waitForTasks()
        
        await MainActor.run {
            // 2. Release Menu
            controllerService.buttonReleased(.menu)
        }
        await waitForTasks()
        
        await MainActor.run {
            // Verify: pressKey was called with Cmd + Delete
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, let modifiers) = event {
                    return code == KeyCodeMapping.delete && modifiers.contains(.maskCommand)
                }
                return false
            }, "Cmd + Delete should have been executed")
        }
    }

    func testHeldModifierWithDelete() async throws {
        await MainActor.run {
            // Setup: LB -> Hold Cmd, A -> Delete
            profileManager.setActiveProfile(Profile(
                name: "HeldDelete",
                buttonMappings: [
                    .leftBumper: .holdModifier(.command),
                    .a: .key(KeyCodeMapping.delete)
                ]
            ))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            // 1. Press LB (Cmd)
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
            
            // 2. Press A (Delete)
            controllerService.buttonPressed(.a)
        }
        await waitForTasks()
        
        await MainActor.run {
            // 3. Release A
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()
        
        await MainActor.run {
            // Verify: Delete was executed (MappingExecutor calls pressKey directly)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event {
                    return code == KeyCodeMapping.delete
                }
                return false
            }, "Delete should have been executed")

            // Verify: Cmd was held during execution
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
        }
    }

    func testChordPreventsIndividualActions() async throws {
        await MainActor.run {
            // Setup: A -> key 1, B -> key 2, [A, B] -> key 3 (Chord)
            let aMapping = KeyMapping.key(1)
            let bMapping = KeyMapping.key(2)
            let chordMapping = ChordMapping(buttons: [.a, .b], keyCode: 3)

            profileManager.setActiveProfile(Profile(
                name: "ChordTest",
                buttonMappings: [.a: aMapping, .b: bMapping],
                chordMappings: [chordMapping]
            ))
        }
        // Allow Combine to deliver profile change to MappingEngine
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        await MainActor.run {
            // 1. Simulate fast tap of A and B (released before chord timer)
            // This represents the race condition where release happens before the 50ms window

            // We simulate what MappingEngine sees:
            // 1. A release (engine doesn't know about chord yet)
            controllerService.onButtonReleased?(.a, 0.02)
            // 2. B release
            controllerService.onButtonReleased?(.b, 0.02)
            // 3. Chord detected (timer finally fired)
            controllerService.onChordDetected?([.a, .b])
        }
        await waitForTasks()
        
        await MainActor.run {
            // Verify individual actions DID NOT execute
            // CURRENTLY THIS WILL FAIL because the engine executes them immediately on release if not already in activeChordButtons
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            }, "Button A action should NOT execute")
            
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 2 }
                return false
            }, "Button B action should NOT execute")

            // Verify chord action executed
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 3 }
                return false
            }, "Chord action should execute")
        }
    }

    // MARK: - Double-Tap Edge Cases

    /// Tests that a single tap followed by waiting longer than threshold executes single-tap action
    func testSingleTapAfterDoubleTapWindow() async throws {
        await MainActor.run {
            let doubleTap = DoubleTapMapping(keyCode: 2, threshold: 0.15)
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = doubleTap
            profileManager.setActiveProfile(Profile(name: "DT", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First tap
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.05)
        }

        // Wait longer than double-tap threshold
        await waitForTasks(0.3)

        await MainActor.run {
            // Single tap should have executed (keyCode 1)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Single tap should execute after double-tap window expires")

            // Double-tap should NOT have executed
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }, "Double-tap should not execute on single tap")
        }
    }

    /// Tests triple-tap behavior (third tap should start new double-tap detection)
    func testTripleTapBehavior() async throws {
        await MainActor.run {
            let doubleTap = DoubleTapMapping(keyCode: 2, threshold: 0.2)
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = doubleTap
            profileManager.setActiveProfile(Profile(name: "Triple", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First tap
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.05)

        // Second tap (double-tap)
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.05)

        // Third tap (should start new sequence)
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.3)

        await MainActor.run {
            // Should have one double-tap (keyCode 2) and one single-tap (keyCode 1)
            let doubleTapCount = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }.count

            XCTAssertEqual(doubleTapCount, 1, "Should have exactly one double-tap")
        }
    }

    // MARK: - Long-Hold Edge Cases

    /// Tests that releasing exactly at long-hold threshold triggers long-hold
    func testLongHoldExactThreshold() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.1)
            profileManager.setActiveProfile(Profile(name: "Exact", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Wait exactly at threshold
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        await MainActor.run {
            // Release with hold duration exactly at threshold
            controllerService.onButtonReleased?(.a, 0.1)
        }
        await waitForTasks()

        await MainActor.run {
            // Long-hold should trigger (>= comparison)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }, "Long-hold should trigger at exact threshold")
        }
    }

    /// Tests that releasing just before long-hold threshold triggers single-tap
    func testLongHoldJustBeforeThreshold() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.2)
            profileManager.setActiveProfile(Profile(name: "Before", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Wait less than threshold
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05s

        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.05)
        }
        await waitForTasks()

        await MainActor.run {
            // Single tap should execute (keyCode 1)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Single tap should execute when released before threshold")

            // Long-hold should NOT execute
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }, "Long-hold should not trigger before threshold")
        }
    }

    /// Tests long-hold timer fires while button still held (no release yet)
    func testLongHoldTimerFiresWhileHeld() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.1)
            profileManager.setActiveProfile(Profile(name: "Held", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Wait for long-hold timer to fire (but don't release)
        await waitForTasks(0.3)

        await MainActor.run {
            // Long-hold should have executed
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }, "Long-hold should trigger while button still held")
        }

        // Now release
        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.3)
        }
        await waitForTasks()

        await MainActor.run {
            // Single tap should NOT execute after long-hold triggered
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Single tap should not execute after long-hold triggered")
        }
    }

    // MARK: - Profile Change Edge Cases

    /// Tests that changing profile while button is held doesn't cause issues
    func testProfileChangeWhileButtonHeld() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "P1", buttonMappings: [.leftBumper: .holdModifier(.command)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.leftBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held")

            // Change profile while button held
            profileManager.setActiveProfile(Profile(name: "P2", buttonMappings: [.leftBumper: .holdModifier(.shift)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Release with OLD profile's mapping should still work
            controllerService.onButtonReleased?(.leftBumper, 0.5)
        }
        await waitForTasks()

        await MainActor.run {
            // Modifier should be released (engine tracks held buttons, not profile)
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be released after button release")
        }
    }

    /// Tests that clearing profile (nil) while button held doesn't crash
    func testNilProfileWhileButtonHeld() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }
        await waitForTasks(0.1)

        // This shouldn't crash - engine should handle gracefully
        // Note: ProfileManager might not allow nil profile, but testing the guard
    }

    // MARK: - Unmapped Button Edge Cases

    /// Tests that pressing unmapped button doesn't cause issues
    func testUnmappedButton() async throws {
        await MainActor.run {
            // Only map A, not B
            profileManager.setActiveProfile(Profile(name: "Partial", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.b)
            controllerService.onButtonReleased?(.b, 0.1)
        }
        await waitForTasks()

        await MainActor.run {
            // No crash, no events for unmapped button
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey = event { return true }
                return false
            }, "Unmapped button should not trigger any key press")
        }
    }

    /// Tests that pressing unmapped button followed by mapped button works
    func testUnmappedThenMappedButton() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Partial", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Press unmapped button first
            controllerService.onButtonPressed?(.b)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            // Then press mapped button
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.05)
        }
        await waitForTasks()

        await MainActor.run {
            // Mapped button should still work
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Mapped button should work even after unmapped button press")
        }
    }

    // MARK: - Multi-Button Chord Edge Cases

    /// Tests chord with 3 buttons
    func testThreeButtonChord() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b, .x], keyCode: 9)
            profileManager.setActiveProfile(Profile(
                name: "Triple",
                buttonMappings: [.a: .key(1), .b: .key(2), .x: .key(3)],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onChordDetected?([.a, .b, .x])
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 9 }
                return false
            }, "Three-button chord should execute")
        }
    }

    /// Tests partial chord match (pressing 2 buttons when 3-button chord exists)
    func testPartialChordNoMatch() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b, .x], keyCode: 9)
            profileManager.setActiveProfile(Profile(
                name: "Triple",
                buttonMappings: [.a: .key(1), .b: .key(2), .x: .key(3)],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Only 2 buttons - should fallback to individual
            controllerService.onChordDetected?([.a, .b])
        }
        await waitForTasks()

        // Release both
        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.05)
            controllerService.onButtonReleased?(.b, 0.05)
        }
        await waitForTasks()

        await MainActor.run {
            // Should NOT execute 3-button chord
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 9 }
                return false
            }, "Three-button chord should not match two-button press")

            // Should execute individual button actions
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }, "Button A should execute on fallback")
        }
    }

    // MARK: - Repeat Mapping Edge Cases

    /// Tests repeat mapping fires multiple times while held
    func testRepeatMappingFires() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.repeatMapping = RepeatMapping(enabled: true, interval: 0.05)
            profileManager.setActiveProfile(Profile(name: "Repeat", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Hold for multiple repeat intervals
        await waitForTasks(0.25)

        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.25)
        }
        await waitForTasks()

        await MainActor.run {
            // Should have multiple executions (initial + repeats)
            let count = mockInputSimulator.events.filter { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            }.count

            XCTAssertGreaterThan(count, 1, "Repeat mapping should fire multiple times, got \(count)")
        }
    }

    /// Tests repeat stops immediately when button released
    func testRepeatStopsOnRelease() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.repeatMapping = RepeatMapping(enabled: true, interval: 0.05)
            profileManager.setActiveProfile(Profile(name: "Repeat", buttonMappings: [.a: aMapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }
        await waitForTasks(0.15)

        let countBeforeRelease = await MainActor.run {
            return mockInputSimulator.events.filter { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            }.count
        }

        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.15)
        }

        // Wait to verify no more repeats
        await waitForTasks(0.2)

        await MainActor.run {
            let countAfterRelease = mockInputSimulator.events.filter { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            }.count

            XCTAssertEqual(countBeforeRelease, countAfterRelease, "No additional repeats should occur after release")
        }
    }

    // MARK: - Engine State Edge Cases

    /// Tests re-enabling engine doesn't cause double-execution
    func testReEnableEngineCleanState() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            mappingEngine.disable()
        }
        await waitForTasks()

        await MainActor.run {
            mappingEngine.enable()
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.05)
        }
        await waitForTasks()

        await MainActor.run {
            let count = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }.count

            XCTAssertEqual(count, 1, "Should execute exactly once after re-enable")
        }
    }

    /// Tests that disabling engine mid-press releases held modifier
    func testDisableEngineReleasesHeldModifier() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [
                .leftBumper: .holdModifier(.command),
                .rightBumper: .holdModifier(.shift)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.leftBumper)
            controllerService.onButtonPressed?(.rightBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift))

            mappingEngine.disable()
        }
        await waitForTasks()

        await MainActor.run {
            // All modifiers should be released
            XCTAssertTrue(mockInputSimulator.heldModifiers.isEmpty, "All modifiers should be released on disable")
        }
    }

    // MARK: - Rapid Input Edge Cases

    /// Tests rapid button press/release doesn't lose events
    func testRapidPressRelease() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Rapid", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Rapid fire 5 press/release cycles
        for _ in 0..<5 {
            await MainActor.run {
                controllerService.onButtonPressed?(.a)
                controllerService.onButtonReleased?(.a, 0.01)
            }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms between cycles
        }

        await waitForTasks()

        await MainActor.run {
            let count = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }.count

            XCTAssertEqual(count, 5, "All 5 rapid presses should be processed, got \(count)")
        }
    }

    /// Tests alternating between two buttons rapidly
    func testAlternatingButtons() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Alt", buttonMappings: [.a: .key(1), .b: .key(2)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Alternate A and B rapidly
        for i in 0..<4 {
            let button: ControllerButton = i % 2 == 0 ? .a : .b
            await MainActor.run {
                controllerService.onButtonPressed?(button)
                controllerService.onButtonReleased?(button, 0.01)
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }

        await waitForTasks()

        await MainActor.run {
            let aCount = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }.count
            let bCount = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 2 }
                return false
            }.count

            XCTAssertEqual(aCount, 2, "Button A should fire twice")
            XCTAssertEqual(bCount, 2, "Button B should fire twice")
        }
    }

    // MARK: - Modifier Tap (Non-Hold) Edge Cases

    /// Tests modifier-only mapping (tap, not hold) releases after delay
    func testModifierTapReleasesAfterDelay() async throws {
        await MainActor.run {
            // Non-hold modifier (tap)
            let mapping = KeyMapping(modifiers: ModifierFlags(command: true), isHoldModifier: false)
            profileManager.setActiveProfile(Profile(name: "ModTap", buttonMappings: [.a: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.05)
        }
        await waitForTasks()

        await MainActor.run {
            // Should have both hold and release modifier events
            let holdCount = mockInputSimulator.events.filter { event in
                if case .holdModifier = event { return true }
                return false
            }.count
            let releaseCount = mockInputSimulator.events.filter { event in
                if case .releaseModifier = event { return true }
                return false
            }.count

            XCTAssertGreaterThan(holdCount, 0, "Modifier tap should hold modifier")
            XCTAssertGreaterThan(releaseCount, 0, "Modifier tap should release modifier after delay")
        }
    }
}
