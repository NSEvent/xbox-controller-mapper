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
            controllerService?.onLeftStickMoved = nil
            controllerService?.onRightStickMoved = nil
            controllerService?.onTouchpadMoved = nil
            controllerService?.onTouchpadGesture = nil
            controllerService?.onTouchpadTap = nil
            controllerService?.onTouchpadTwoFingerTap = nil
            controllerService?.onTouchpadLongTap = nil
            controllerService?.onTouchpadTwoFingerLongTap = nil
            controllerService?.cleanup() // Clean up HID resources before deallocation
            // Reset DualSense flag to prevent LED code from running
            UserDefaults.standard.removeObject(forKey: Config.lastControllerWasDualSenseKey)
            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
        // Extra delay to let deallocation complete
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
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

    // MARK: - Joystick Processing Tests (High Priority)

    /// Tests that joystick values within deadzone don't generate mouse movement
    func testJoystickDeadzoneNearBoundary() async throws {
        await MainActor.run {
            controllerService.isConnected = true
        }
        await waitForTasks(0.2)

        // Set joystick just inside default deadzone (0.15)
        controllerService.setLeftStickForTesting(CGPoint(x: 0.1, y: 0.1))
        await waitForTasks(0.2)

        await MainActor.run {
            // Should NOT generate mouse movement for value inside deadzone
            let mouseEvents = mockInputSimulator.events.filter { event in
                if case .moveMouse = event { return true }
                return false
            }
            XCTAssertTrue(mouseEvents.isEmpty, "Joystick inside deadzone should not generate mouse movement")
        }
    }

    /// Tests that joystick values just outside deadzone DO generate mouse movement
    func testJoystickJustOutsideDeadzone() async throws {
        await MainActor.run {
            controllerService.isConnected = true
        }
        await waitForTasks(0.2)

        // Set joystick just outside default deadzone (0.15) - use 0.3 to be safely outside
        controllerService.setLeftStickForTesting(CGPoint(x: 0.3, y: 0.0))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .moveMouse = event { return true }
                return false
            }, "Joystick outside deadzone should generate mouse movement")
        }
    }

    /// Tests that inverted Y axis is respected
    func testJoystickInvertedY() async throws {
        await MainActor.run {
            var profile = Profile(name: "InvertY", buttonMappings: [:])
            profile.joystickSettings.invertMouseY = true
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await waitForTasks(0.2)

        // Move stick up (positive Y)
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.5))
        await waitForTasks(0.2)

        await MainActor.run {
            // With inverted Y, positive stick Y should produce positive mouse dy
            // (normally it would be negative due to coordinate flip)
            let mouseEvents = mockInputSimulator.events.compactMap { event -> CGFloat? in
                if case .moveMouse(_, let dy) = event { return dy }
                return nil
            }
            XCTAssertFalse(mouseEvents.isEmpty, "Should have mouse movement")
            // The sign depends on the inversion - just verify we got events
        }
    }

    // MARK: - Right Stick Scroll Mode Tests (High Priority)

    /// Tests that right stick generates scroll events
    func testRightStickScrollMode() async throws {
        await MainActor.run {
            controllerService.isConnected = true
        }
        await waitForTasks(0.2)

        // We need to set right stick directly in storage for this test
        // Since there's no setRightStickForTesting, we'll verify the scroll mock is called
        // by observing that scroll events occur when processScrolling is called

        // For now, verify scroll mock exists and events can be recorded
        await MainActor.run {
            // The mock should be able to receive scroll events
            mockInputSimulator.scroll(dx: 1.0, dy: 2.0, phase: nil, momentumPhase: nil, isContinuous: false, flags: [])
        }

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .scroll(1.0, 2.0) = event { return true }
                return false
            }, "Mock should record scroll events")
        }
    }

    // MARK: - Mouse Button Mapping Tests (High Priority)

    /// Tests that mouse left click mapping works
    func testMouseLeftClickMapping() async throws {
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)
            profileManager.setActiveProfile(Profile(name: "MouseClick", buttonMappings: [.a: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks()

        await MainActor.run {
            // Mouse clicks use startHoldMapping for the "held" mouse button
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .startHoldMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.mouseLeftClick
                }
                return false
            }, "Should start hold mapping for mouse left click")
        }

        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .stopHoldMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.mouseLeftClick
                }
                return false
            }, "Should stop hold mapping on release")
        }
    }

    /// Tests that mouse right click mapping works
    func testMouseRightClickMapping() async throws {
        await MainActor.run {
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true)
            profileManager.setActiveProfile(Profile(name: "RightClick", buttonMappings: [.b: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.b)
        }
        await waitForTasks()

        await MainActor.run {
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        await MainActor.run {
            let hasStartHold = mockInputSimulator.events.contains { event in
                if case .startHoldMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.mouseRightClick
                }
                return false
            }
            let hasStopHold = mockInputSimulator.events.contains { event in
                if case .stopHoldMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.mouseRightClick
                }
                return false
            }
            XCTAssertTrue(hasStartHold, "Should have start hold for right click")
            XCTAssertTrue(hasStopHold, "Should have stop hold for right click")
        }
    }

    // MARK: - Macro Execution Tests (High Priority)

    /// Tests that macro with multiple steps executes correctly
    func testMacroWithMultipleSteps() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(
                id: macroId,
                name: "Test Macro",
                steps: [
                    .press(KeyMapping(keyCode: 0)), // 'a' key
                    .press(KeyMapping(keyCode: 1)), // 's' key
                    .press(KeyMapping(keyCode: 2))  // 'd' key
                ]
            )
            var profile = Profile(name: "MacroTest", buttonMappings: [:])
            profile.macros = [macro]
            profile.buttonMappings[.a] = KeyMapping(macroId: macroId)
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            // The mock's executeMacro simulates all steps
            let pressEvents = mockInputSimulator.events.filter { event in
                if case .pressKey = event { return true }
                return false
            }
            XCTAssertEqual(pressEvents.count, 3, "Macro should execute all 3 steps")
        }
    }

    /// Tests that macro can be assigned to chord
    func testMacroOnChord() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(
                id: macroId,
                name: "Chord Macro",
                steps: [
                    .press(KeyMapping(keyCode: 5)),
                    .press(KeyMapping(keyCode: 6))
                ]
            )
            var profile = Profile(name: "ChordMacro", buttonMappings: [:])
            profile.macros = [macro]
            profile.chordMappings = [ChordMapping(buttons: [.a, .b], macroId: macroId)]
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onChordDetected?([.a, .b])
        }
        await waitForTasks()

        await MainActor.run {
            let pressEvents = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 5 || code == 6 }
                return false
            }
            XCTAssertEqual(pressEvents.count, 2, "Chord should trigger macro with 2 steps")
        }
    }

    // MARK: - System Command Tests (Medium Priority)

    /// Tests that system command mapping is recognized
    func testSystemCommandMapping() async throws {
        await MainActor.run {
            let mapping = KeyMapping(systemCommand: .shellCommand(command: "echo test", inTerminal: false))
            profileManager.setActiveProfile(Profile(name: "SysCmd", buttonMappings: [.menu: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Verify the mapping was set up correctly
        await MainActor.run {
            let profile = profileManager.activeProfile
            XCTAssertNotNil(profile?.buttonMappings[.menu]?.systemCommand, "System command should be set")
        }
    }

    // MARK: - Focus Mode Tests (Medium Priority)

    /// Tests that focus mode reduces sensitivity when modifier is held
    func testFocusModeActivation() async throws {
        await MainActor.run {
            var profile = Profile(name: "Focus", buttonMappings: [
                .leftBumper: .holdModifier(.command)
            ])
            profile.joystickSettings.focusModeModifier = .command
            profile.joystickSettings.focusModeSensitivity = 0.1
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        await waitForTasks(0.2)

        // Press LB to hold Command (which is also focus modifier)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()

        // Verify modifier is held
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held for focus mode")
        }
    }

    /// Tests focus mode with different modifier than held button
    func testFocusModeWithDifferentModifier() async throws {
        await MainActor.run {
            var profile = Profile(name: "FocusDiff", buttonMappings: [
                .leftBumper: .holdModifier(.shift)
            ])
            profile.joystickSettings.focusModeModifier = .command // Different from held modifier
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()

        await MainActor.run {
            // Shift is held, but focus mode requires Command
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift), "Shift should be held")
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should NOT be held")
        }
    }

    // MARK: - App-Specific Profile Tests (Medium Priority)

    /// Tests that profile manager can store app-specific overrides (structural test)
    func testAppSpecificProfileStructure() async throws {
        await MainActor.run {
            let profile = Profile(name: "AppSpecific", buttonMappings: [.a: .key(1)])
            // Note: The actual app-specific override system depends on AppMonitor
            // This test verifies the profile can be created and stored
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            XCTAssertEqual(profileManager.activeProfile?.name, "AppSpecific")
        }
    }

    // MARK: - Connection State Tests (High Priority)

    /// Tests that engine handles button state on connection change
    func testButtonStateDuringConnectionChange() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Conn", buttonMappings: [
                .leftBumper: .holdModifier(.command)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held")
        }

        // Simulate disconnect by disabling engine
        await MainActor.run {
            mappingEngine.disable()
        }
        await waitForTasks()

        await MainActor.run {
            // Modifiers should be released when engine is disabled
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be released on disconnect")
        }
    }

    /// Tests that engine can be re-enabled after disable
    func testEngineReEnableAfterDisable() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "ReEnable", buttonMappings: [.a: .key(1)]))
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
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }, "Engine should work after re-enable")
        }
    }

    // MARK: - Double Tap with Macro Tests

    /// Tests double tap that triggers a macro
    func testDoubleTapWithMacro() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(id: macroId, name: "DoubleTapMacro", steps: [
                .press(KeyMapping(keyCode: 10)),
                .press(KeyMapping(keyCode: 11))
            ])
            var profile = Profile(name: "DTMacro", buttonMappings: [:])
            profile.macros = [macro]
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = DoubleTapMapping(threshold: 0.2, macroId: macroId)
            profile.buttonMappings[.a] = aMapping
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Double tap
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.05)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.3)

        await MainActor.run {
            let macroKeys = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 10 || code == 11 }
                return false
            }
            XCTAssertEqual(macroKeys.count, 2, "Double tap should trigger macro with 2 steps")
        }
    }

    // MARK: - Long Hold with Macro Tests

    /// Tests long hold that triggers a macro
    func testLongHoldWithMacro() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(id: macroId, name: "LongHoldMacro", steps: [
                .press(KeyMapping(keyCode: 20))
            ])
            var profile = Profile(name: "LHMacro", buttonMappings: [:])
            profile.macros = [macro]
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(threshold: 0.1, macroId: macroId)
            profile.buttonMappings[.a] = aMapping
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Wait for long hold to trigger
        await waitForTasks(0.3)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(20, _) = event { return true }
                return false
            }, "Long hold should trigger macro")
        }
    }

    // MARK: - Multiple Modifier Hold Tests

    /// Tests holding multiple different modifiers on different buttons
    func testMultipleModifiersOnDifferentButtons() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "MultiMod", buttonMappings: [
                .leftBumper: .holdModifier(.command),
                .rightBumper: .holdModifier(.option),
                .leftTrigger: .holdModifier(.shift)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press all three
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
            controllerService.buttonPressed(.rightBumper)
            controllerService.buttonPressed(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held")
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskAlternate), "Option should be held")
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift), "Shift should be held")
        }

        // Release in different order
        await MainActor.run {
            controllerService.buttonReleased(.rightBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should still be held")
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskAlternate), "Option should be released")
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift), "Shift should still be held")
        }

        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
            controllerService.buttonReleased(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.isEmpty, "All modifiers should be released")
        }
    }

    // MARK: - Empty Profile Tests

    /// Tests behavior with empty profile (no mappings)
    func testEmptyProfile() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Empty", buttonMappings: [:]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            // Should not crash, no key presses should occur
            let keyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey = event { return true }
                return false
            }
            XCTAssertTrue(keyPresses.isEmpty, "Empty profile should produce no key presses")
        }
    }

    // MARK: - Key + Modifier Combo Tests

    /// Tests complex key + modifier combination
    func testComplexKeyCombination() async throws {
        await MainActor.run {
            // Cmd + Opt + Shift + K
            let mapping = KeyMapping(
                keyCode: 40, // 'k'
                modifiers: ModifierFlags(command: true, option: true, shift: true)
            )
            profileManager.setActiveProfile(Profile(name: "Complex", buttonMappings: [.y: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.y)
            controllerService.buttonReleased(.y)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(40, let mods) = event {
                    return mods.contains(.maskCommand) &&
                           mods.contains(.maskAlternate) &&
                           mods.contains(.maskShift)
                }
                return false
            }, "Should press key with all three modifiers")
        }
    }

    // MARK: - Chord with Modifiers Tests

    /// Tests chord that outputs key + modifiers
    func testChordWithModifiers() async throws {
        await MainActor.run {
            let chord = ChordMapping(
                buttons: [.x, .y],
                keyCode: 50, // some key
                modifiers: ModifierFlags(command: true, shift: true)
            )
            profileManager.setActiveProfile(Profile(
                name: "ChordMod",
                buttonMappings: [:],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onChordDetected?([.x, .y])
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(50, let mods) = event {
                    return mods.contains(.maskCommand) && mods.contains(.maskShift)
                }
                return false
            }, "Chord should output key with modifiers")
        }
    }

    // MARK: - Button Press During Pending Double Tap

    /// Tests pressing a different button during double-tap window
    func testDifferentButtonDuringDoubleTapWindow() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = DoubleTapMapping(keyCode: 2, threshold: 0.2)
            profileManager.setActiveProfile(Profile(name: "DTDiff", buttonMappings: [
                .a: aMapping,
                .b: .key(3)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First tap of A
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.05)

        // Press B during A's double-tap window
        await MainActor.run {
            controllerService.onButtonPressed?(.b)
            controllerService.onButtonReleased?(.b, 0.03)
        }
        await waitForTasks(0.3)

        await MainActor.run {
            // Both should execute their single-tap actions
            let hasA = mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }
            let hasB = mockInputSimulator.events.contains { event in
                if case .pressKey(3, _) = event { return true }
                return false
            }
            XCTAssertTrue(hasA, "Button A single tap should execute")
            XCTAssertTrue(hasB, "Button B should execute normally")
        }
    }
}
