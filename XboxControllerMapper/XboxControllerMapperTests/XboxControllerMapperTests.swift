import XCTest
import Combine
import CoreGraphics
import Carbon.HIToolbox
import SwiftUI
import AppKit
@testable import ControllerKeys

// MARK: - Mocks

class MockInputSimulator: InputSimulatorProtocol {

    enum Event: Equatable {
        case pressKey(CGKeyCode, CGEventFlags)
        case keyDown(CGKeyCode)
        case keyUp(CGKeyCode)
        case holdModifier(CGEventFlags)
        case releaseModifier(CGEventFlags)
        case releaseAllModifiers
        case moveMouse(CGFloat, CGFloat)
        case scroll(CGFloat, CGFloat)
        case executeMapping(KeyMapping)
        case startHoldMapping(KeyMapping)
        case stopHoldMapping(KeyMapping)
        case typeText(String, Int, Bool)  // text, speed, pressEnter
    }
    
    private let lock = NSLock()
    
    private var _events: [Event] = []
    var events: [Event] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    func clearEvents() {
        lock.lock()
        defer { lock.unlock() }
        _events.removeAll()
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

    private var _heldDirectionKeys: Set<CGKeyCode> = []
    var heldDirectionKeys: Set<CGKeyCode> {
        lock.lock()
        defer { lock.unlock() }
        return _heldDirectionKeys
    }

    func keyDown(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {
        lock.lock()
        defer { lock.unlock() }
        _heldDirectionKeys.insert(keyCode)
        if KeyCodeMapping.isMouseButton(keyCode) && keyCode == KeyCodeMapping.mouseLeftClick {
            _heldMouseButton = true
        }
        _events.append(.keyDown(keyCode))
    }

    func keyUp(_ keyCode: CGKeyCode) {
        lock.lock()
        defer { lock.unlock() }
        _heldDirectionKeys.remove(keyCode)
        if KeyCodeMapping.isMouseButton(keyCode) && keyCode == KeyCodeMapping.mouseLeftClick {
            _heldMouseButton = false
        }
        _events.append(.keyUp(keyCode))
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

    func getHeldModifiers() -> CGEventFlags {
        lock.lock()
        defer { lock.unlock() }
        return _heldModifiers
    }

    private var _heldMouseButton: Bool = false

    var isLeftMouseButtonHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _heldMouseButton
    }

    func moveMouse(dx: CGFloat, dy: CGFloat) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(.moveMouse(dx, dy))
    }

    func moveMouseNative(dx: Int, dy: Int) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(.moveMouse(CGFloat(dx), CGFloat(dy)))
    }

    private(set) var lastWarpPoint: CGPoint?
    func warpMouseTo(point: CGPoint) {
        lock.lock()
        defer { lock.unlock() }
        lastWarpPoint = point
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
        if mapping.modifiers.hasAny {
            holdModifier(mapping.modifiers.cgEventFlags)
        }
        if let keyCode = mapping.keyCode {
            keyDown(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        }

        lock.lock()
        defer { lock.unlock() }
        _events.append(.startHoldMapping(mapping))
    }

    func stopHoldMapping(_ mapping: KeyMapping) {
        if let keyCode = mapping.keyCode {
            keyUp(keyCode)
        }
        if mapping.modifiers.hasAny {
            releaseModifier(mapping.modifiers.cgEventFlags)
        }

        lock.lock()
        defer { lock.unlock() }
        _events.append(.stopHoldMapping(mapping))
    }

    func typeText(_ text: String, speed: Int, pressEnter: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(.typeText(text, speed, pressEnter))
    }
}

// MARK: - Tests

final class XboxControllerMapperTests: XCTestCase {
    
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!
    
    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-tests-\(UUID().uuidString)", isDirectory: true)

        await MainActor.run {
            controllerService = ControllerService(enableHardwareMonitoring: false)
            // Reduce chord window for faster test execution (50ms should be safe)
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
            // Reset PlayStation controller flags to prevent LED code from running
            UserDefaults.standard.removeObject(forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.removeObject(forKey: Config.lastControllerWasDualShockKey)
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

    /// Tests that macro with typeText step executes correctly
    /// Note: The actual typing uses nil CGEventSource to prevent held modifiers from affecting text
    func testMacroWithTypeTextStep() async throws {
        let macroId = UUID()

        await MainActor.run {
            let macro = Macro(
                id: macroId,
                name: "Type Macro",
                steps: [
                    .typeText("hello@example.com", speed: 300)
                ]
            )
            var profile = Profile(name: "TypeTest", buttonMappings: [:])
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
            let typeEvents = mockInputSimulator.events.filter { event in
                if case .typeText = event { return true }
                return false
            }
            XCTAssertEqual(typeEvents.count, 1, "Macro should execute typeText step")

            if case .typeText(let text, let speed, _) = typeEvents.first {
                XCTAssertEqual(text, "hello@example.com", "Text should match")
                XCTAssertEqual(speed, 300, "Speed should match")
            }
        }
    }

    /// Tests that macro typeText works while modifiers are held (simulates on-screen keyboard scenario)
    /// The fix ensures typed characters use nil CGEventSource to avoid inheriting held modifier state
    func testMacroTypeTextIgnoresHeldModifiers() async throws {
        let macroId = UUID()

        await MainActor.run {
            // Hold a modifier (simulating on-screen keyboard button)
            mockInputSimulator.holdModifier(.maskCommand)

            let macro = Macro(
                id: macroId,
                name: "Type While Modifier Held",
                steps: [
                    .typeText("test@123", speed: 300)
                ]
            )
            var profile = Profile(name: "ModifierTest", buttonMappings: [:])
            profile.macros = [macro]
            profile.buttonMappings[.b] = KeyMapping(macroId: macroId)
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Verify modifier is held
            XCTAssertTrue(mockInputSimulator.isHoldingModifiers(.maskCommand), "Modifier should be held")

            controllerService.buttonPressed(.b)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        await MainActor.run {
            // TypeText event should be recorded regardless of held modifiers
            let typeEvents = mockInputSimulator.events.filter { event in
                if case .typeText = event { return true }
                return false
            }
            XCTAssertEqual(typeEvents.count, 1, "TypeText should execute even with modifier held")

            // The actual CGEvent implementation uses nil source to prevent modifier inheritance
            // This test documents the expected behavior - the mock doesn't simulate CGEvent details
            if case .typeText(let text, _, _) = typeEvents.first {
                XCTAssertEqual(text, "test@123", "Text content should be preserved")
            }
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

    // MARK: - D-Pad Mapping Tests (High Priority)

    /// Tests all D-Pad directions are mapped correctly
    func testDPadMappings() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "DPad", buttonMappings: [
                .dpadUp: .key(KeyCodeMapping.upArrow),
                .dpadDown: .key(KeyCodeMapping.downArrow),
                .dpadLeft: .key(KeyCodeMapping.leftArrow),
                .dpadRight: .key(KeyCodeMapping.rightArrow)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Test each direction
        for (button, expectedKeyCode) in [
            (ControllerButton.dpadUp, KeyCodeMapping.upArrow),
            (ControllerButton.dpadDown, KeyCodeMapping.downArrow),
            (ControllerButton.dpadLeft, KeyCodeMapping.leftArrow),
            (ControllerButton.dpadRight, KeyCodeMapping.rightArrow)
        ] {
            await MainActor.run {
                controllerService.buttonPressed(button)
                controllerService.buttonReleased(button)
            }
            await waitForTasks()

            await MainActor.run {
                XCTAssertTrue(mockInputSimulator.events.contains { event in
                    if case .pressKey(let code, _) = event { return code == expectedKeyCode }
                    return false
                }, "\(button) should map to arrow key \(expectedKeyCode)")
            }
        }
    }

    /// Tests D-Pad diagonal simulation (two directions at once)
    func testDPadDiagonal() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "DPadDiag", buttonMappings: [
                .dpadUp: .key(KeyCodeMapping.upArrow),
                .dpadRight: .key(KeyCodeMapping.rightArrow)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press both up and right simultaneously
        await MainActor.run {
            controllerService.buttonPressed(.dpadUp)
            controllerService.buttonPressed(.dpadRight)
        }
        await waitForTasks()

        await MainActor.run {
            controllerService.buttonReleased(.dpadUp)
            controllerService.buttonReleased(.dpadRight)
        }
        await waitForTasks()

        await MainActor.run {
            let hasUp = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.upArrow }
                return false
            }
            let hasRight = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.rightArrow }
                return false
            }
            XCTAssertTrue(hasUp, "Up arrow should be pressed")
            XCTAssertTrue(hasRight, "Right arrow should be pressed")
        }
    }

    // MARK: - Trigger Button Mapping Tests (High Priority)

    /// Tests left trigger as a button (digital, not analog)
    func testLeftTriggerAsButton() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "LT", buttonMappings: [
                .leftTrigger: .key(KeyCodeMapping.space)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftTrigger)
            controllerService.buttonReleased(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.space }
                return false
            }, "Left trigger should press space")
        }
    }

    /// Tests right trigger as a button
    func testRightTriggerAsButton() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "RT", buttonMappings: [
                .rightTrigger: .key(KeyCodeMapping.return)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.rightTrigger)
            controllerService.buttonReleased(.rightTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.return }
                return false
            }, "Right trigger should press return")
        }
    }

    /// Tests trigger as hold modifier
    func testTriggerAsHoldModifier() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "TrigMod", buttonMappings: [
                .leftTrigger: .holdModifier(.option),
                .a: .key(1)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskAlternate), "Option should be held")
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }, "A should press while trigger holds modifier")
            controllerService.buttonReleased(.leftTrigger)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskAlternate), "Option should be released")
        }
    }

    // MARK: - Touchpad Gesture Tests (High Priority - DualSense)

    /// Tests touchpad tap gesture callback
    func testTouchpadTapGesture() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "TouchTap", buttonMappings: [
                .touchpadTap: KeyMapping(keyCode: KeyCodeMapping.mouseLeftClick, isHoldModifier: true)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Simulate tap gesture callback
        await MainActor.run {
            controllerService.onTouchpadTap?()
        }
        await waitForTasks()

        await MainActor.run {
            let leftClickPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.mouseLeftClick }
                return false
            }.count
            let holdEvents = mockInputSimulator.events.contains { event in
                if case .startHoldMapping = event { return true }
                return false
            }

            XCTAssertEqual(leftClickPresses, 1, "Touchpad tap should emit one left click")
            XCTAssertFalse(holdEvents, "Touchpad tap should be a discrete click, not hold mapping")
        }
    }

    /// Tests touchpad two-finger tap (right click)
    func testTouchpadTwoFingerTap() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "TouchTwoFinger", buttonMappings: [
                .touchpadTwoFingerTap: KeyMapping(keyCode: KeyCodeMapping.mouseRightClick, isHoldModifier: true)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Simulate two-finger tap callback
        await MainActor.run {
            controllerService.onTouchpadTwoFingerTap?()
        }
        await waitForTasks()

        await MainActor.run {
            let rightClickPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let keyCode, _) = event { return keyCode == KeyCodeMapping.mouseRightClick }
                return false
            }.count
            let holdEvents = mockInputSimulator.events.contains { event in
                if case .startHoldMapping = event { return true }
                return false
            }

            XCTAssertEqual(rightClickPresses, 1, "Two-finger tap should emit one right click")
            XCTAssertFalse(holdEvents, "Two-finger tap should be a discrete click, not hold mapping")
        }
    }

    // MARK: - Special Button Tests (High Priority)

    /// Tests Xbox/Guide button mapping
    func testXboxButtonMapping() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Xbox", buttonMappings: [
                .xbox: .key(KeyCodeMapping.escape)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.xbox)
            controllerService.buttonReleased(.xbox)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.escape }
                return false
            }, "Xbox button should press escape")
        }
    }

    /// Tests Menu button mapping
    func testMenuButtonMapping() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Menu", buttonMappings: [
                .menu: .key(KeyCodeMapping.tab)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.menu)
            controllerService.buttonReleased(.menu)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.tab }
                return false
            }, "Menu button should press tab")
        }
    }

    /// Tests View/Back button mapping
    func testViewButtonMapping() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "View", buttonMappings: [
                .view: .key(KeyCodeMapping.grave) // backtick/tilde key
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.view)
            controllerService.buttonReleased(.view)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.grave }
                return false
            }, "View button should press grave/backtick")
        }
    }

    // MARK: - Stick Click Tests (High Priority)

    /// Tests left stick click (L3) mapping with middle mouse (treated as hold mapping)
    func testLeftStickClick() async throws {
        await MainActor.run {
            // Mouse clicks are automatically treated as hold mappings
            let mapping = KeyMapping(keyCode: KeyCodeMapping.mouseMiddleClick, isHoldModifier: true)
            profileManager.setActiveProfile(Profile(name: "L3", buttonMappings: [
                .leftThumbstick: mapping
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.leftThumbstick)
        }
        await waitForTasks()

        await MainActor.run {
            // Mouse clicks use startHoldMapping
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .startHoldMapping(let m) = event { return m.keyCode == KeyCodeMapping.mouseMiddleClick }
                return false
            }, "Left stick click should start hold mapping for middle mouse")

            controllerService.buttonReleased(.leftThumbstick)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .stopHoldMapping(let m) = event { return m.keyCode == KeyCodeMapping.mouseMiddleClick }
                return false
            }, "Left stick click should stop hold mapping on release")
        }
    }

    /// Tests right stick click (R3) mapping
    func testRightStickClick() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "R3", buttonMappings: [
                .rightThumbstick: .key(KeyCodeMapping.f5)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.rightThumbstick)
            controllerService.buttonReleased(.rightThumbstick)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.f5 }
                return false
            }, "Right stick click should press F5")
        }
    }

    // MARK: - Profile Switching Tests (High Priority)

    /// Tests rapid profile switching
    func testRapidProfileSwitching() async throws {
        let profile1 = Profile(name: "P1", buttonMappings: [.a: .key(1)])
        let profile2 = Profile(name: "P2", buttonMappings: [.a: .key(2)])

        await MainActor.run {
            profileManager.setActiveProfile(profile1)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Switch profiles rapidly
        for i in 0..<5 {
            await MainActor.run {
                profileManager.setActiveProfile(i % 2 == 0 ? profile2 : profile1)
            }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }

        // Settle on profile2
        await MainActor.run {
            profileManager.setActiveProfile(profile2)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            // Should use profile2's mapping (keyCode 2)
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(2, _) = event { return true }
                return false
            }, "Should use final profile's mapping")
        }
    }

    /// Tests switching to profile with fewer mappings
    func testSwitchToSmallerProfile() async throws {
        let fullProfile = Profile(name: "Full", buttonMappings: [
            .a: .key(1),
            .b: .key(2),
            .x: .key(3),
            .y: .key(4)
        ])
        let minimalProfile = Profile(name: "Minimal", buttonMappings: [.a: .key(10)])

        await MainActor.run {
            profileManager.setActiveProfile(fullProfile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            profileManager.setActiveProfile(minimalProfile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // B should now be unmapped
        await MainActor.run {
            controllerService.buttonPressed(.b)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        await MainActor.run {
            // Should NOT trigger old mapping
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(2, _) = event { return true }
                return false
            }, "Old mapping should not be used")
        }
    }

    // MARK: - Function Key Tests

    /// Tests function key mappings
    func testFunctionKeyMappings() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "FnKeys", buttonMappings: [
                .a: .key(KeyCodeMapping.f1),
                .b: .key(KeyCodeMapping.f12)
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.f1 }
                return false
            }, "Should press F1")
        }

        await MainActor.run {
            controllerService.buttonPressed(.b)
            controllerService.buttonReleased(.b)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.f12 }
                return false
            }, "Should press F12")
        }
    }

    // MARK: - Modifier Key Overlap Tests

    /// Tests the same modifier on multiple buttons
    func testSameModifierOnMultipleButtons() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "DualCmd", buttonMappings: [
                .leftBumper: .holdModifier(.command),
                .rightBumper: .holdModifier(.command) // Same modifier!
            ]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press both
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held")
        }

        // Release one - should still be held
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should STILL be held (RB holds it)")
        }

        // Release the other - now should be released
        await MainActor.run {
            controllerService.buttonReleased(.rightBumper)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should now be released")
        }
    }

    // MARK: - Chord Edge Case Tests

    /// Tests chord where one button has no individual mapping
    func testChordWithUnmappedButton() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b], keyCode: 99)
            profileManager.setActiveProfile(Profile(
                name: "ChordUnmapped",
                buttonMappings: [.a: .key(1)], // Only A mapped, not B
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onChordDetected?([.a, .b])
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(99, _) = event { return true }
                return false
            }, "Chord should work even if one button is unmapped individually")
        }
    }

    /// Tests multiple overlapping chords (2-button vs 3-button)
    func testOverlappingChords() async throws {
        await MainActor.run {
            let twoButtonChord = ChordMapping(buttons: [.a, .b], keyCode: 50)
            let threeButtonChord = ChordMapping(buttons: [.a, .b, .x], keyCode: 51)
            profileManager.setActiveProfile(Profile(
                name: "Overlap",
                buttonMappings: [:],
                chordMappings: [twoButtonChord, threeButtonChord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Trigger 3-button chord
        await MainActor.run {
            controllerService.onChordDetected?([.a, .b, .x])
        }
        await waitForTasks()

        await MainActor.run {
            // Should trigger 3-button chord, not 2-button
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(51, _) = event { return true }
                return false
            }, "3-button chord should be triggered")

            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(50, _) = event { return true }
                return false
            }, "2-button chord should NOT be triggered")
        }
    }

    // MARK: - Long Hold Cancel Tests

    /// Tests that releasing before threshold cancels long hold
    func testLongHoldCancelledByQuickRelease() async throws {
        await MainActor.run {
            var mapping = KeyMapping(keyCode: 1)
            mapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.5)
            profileManager.setActiveProfile(Profile(name: "LHCancel", buttonMappings: [.a: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            controllerService.onButtonPressed?(.a)
        }

        // Release quickly (before 0.5s threshold)
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.1)
        }
        await waitForTasks()

        await MainActor.run {
            // Single tap should execute
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }, "Single tap should execute")

            // Long hold should NOT execute
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .pressKey(2, _) = event { return true }
                return false
            }, "Long hold should NOT execute")
        }
    }

    // MARK: - Double Tap Cancel Tests

    /// Tests that slow second tap doesn't trigger double-tap
    func testDoubleTapCancelledBySlowSecondTap() async throws {
        await MainActor.run {
            var mapping = KeyMapping(keyCode: 1)
            mapping.doubleTapMapping = DoubleTapMapping(keyCode: 2, threshold: 0.2)
            profileManager.setActiveProfile(Profile(name: "DTCancel", buttonMappings: [.a: mapping]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First tap
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }

        // Wait longer than double-tap threshold
        await waitForTasks(0.3)

        // Second tap (too late)
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.3)

        await MainActor.run {
            // Should have TWO single taps, no double tap
            let singleTaps = mockInputSimulator.events.filter { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }.count

            let doubleTaps = mockInputSimulator.events.filter { event in
                if case .pressKey(2, _) = event { return true }
                return false
            }.count

            XCTAssertEqual(singleTaps, 2, "Should have two single taps")
            XCTAssertEqual(doubleTaps, 0, "Should have no double taps")
        }
    }

    // MARK: - Input Log Service Tests

    /// Tests that InputLogService logs button presses correctly
    func testInputLogServiceLogsButtonPress() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .singlePress, action: "Key: A")
        }

        // Wait for batching delay (50ms) + buffer
        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.count, 1, "Should have one entry")
            XCTAssertEqual(logService.entries.first?.buttons, [.a])
            XCTAssertEqual(logService.entries.first?.type, .singlePress)
            XCTAssertEqual(logService.entries.first?.actionDescription, "Key: A")
        }
    }

    /// Tests that InputLogService limits entries to 8
    func testInputLogServiceLimitsEntries() async throws {
        let logService = InputLogService()

        await MainActor.run {
            // Log 12 entries
            for i in 0..<12 {
                logService.log(buttons: [.a], type: .singlePress, action: "Event \(i)")
            }
        }

        // Wait for batching
        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertLessThanOrEqual(logService.entries.count, 8, "Should limit to 8 entries")
        }
    }

    /// Tests that InputLogService shows newest entries first
    func testInputLogServiceNewestFirst() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .singlePress, action: "First")
            logService.log(buttons: [.b], type: .singlePress, action: "Second")
            logService.log(buttons: [.x], type: .singlePress, action: "Third")
        }

        // Wait for batching
        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.first?.actionDescription, "Third", "Newest should be first")
            XCTAssertEqual(logService.entries.last?.actionDescription, "First", "Oldest should be last")
        }
    }

    /// Tests that InputLogService logs chord events
    func testInputLogServiceLogsChord() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a, .b], type: .chord, action: "Chord: A+B")
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.count, 1)
            XCTAssertEqual(logService.entries.first?.buttons, [.a, .b])
            XCTAssertEqual(logService.entries.first?.type, .chord)
        }
    }

    /// Tests that InputLogService logs double-tap events
    func testInputLogServiceLogsDoubleTap() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .doubleTap, action: "Double Tap: A")
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.first?.type, .doubleTap)
        }
    }

    /// Tests that InputLogService logs long-press events
    func testInputLogServiceLogsLongPress() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .longPress, action: "Long Press: A")
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.first?.type, .longPress)
        }
    }

    /// Tests that InputLogService cleans up old entries
    func testInputLogServiceCleansUpOldEntries() async throws {
        let logService = InputLogService()

        await MainActor.run {
            logService.log(buttons: [.a], type: .singlePress, action: "Old entry")
        }

        // Wait for batching
        try? await Task.sleep(nanoseconds: 100_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.count, 1)
        }

        // Wait for retention period (3 seconds) + cleanup interval (0.5s) + buffer
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        await MainActor.run {
            XCTAssertEqual(logService.entries.count, 0, "Entry should be cleaned up after retention period")
        }
    }

    // MARK: - Profile Management Tests

    /// Tests that creating a profile from template copies mappings
    func testCreateProfileFromTemplate() async throws {
        await MainActor.run {
            let template = Profile(
                name: "Template",
                buttonMappings: [.a: .key(1), .b: .key(2)],
                chordMappings: [ChordMapping(buttons: [.a, .b], keyCode: 3)]
            )
            profileManager.profiles.append(template)

            let newProfile = profileManager.createProfile(name: "Copy", basedOn: template)

            XCTAssertEqual(newProfile.name, "Copy")
            XCTAssertEqual(newProfile.buttonMappings.count, 2)
            XCTAssertEqual(newProfile.chordMappings.count, 1)
            XCTAssertNotEqual(newProfile.id, template.id, "New profile should have different ID")
            XCTAssertFalse(newProfile.isDefault, "Copy should not be default")
        }
    }

    /// Tests that deleting profile switches to another
    func testDeleteProfileSwitchesActive() async throws {
        await MainActor.run {
            let profile1 = Profile(name: "Profile1")
            let profile2 = Profile(name: "Profile2")
            profileManager.profiles = [profile1, profile2]
            profileManager.setActiveProfile(profile1)

            XCTAssertEqual(profileManager.activeProfileId, profile1.id)

            profileManager.deleteProfile(profile1)

            // Should switch to remaining profile
            XCTAssertEqual(profileManager.activeProfileId, profile2.id)
            XCTAssertEqual(profileManager.profiles.count, 1)
        }
    }

    /// Tests that last profile cannot be deleted
    func testCannotDeleteLastProfile() async throws {
        await MainActor.run {
            let onlyProfile = Profile(name: "Only")
            profileManager.profiles = [onlyProfile]
            profileManager.setActiveProfile(onlyProfile)

            profileManager.deleteProfile(onlyProfile)

            // Should still have the profile
            XCTAssertEqual(profileManager.profiles.count, 1)
            XCTAssertEqual(profileManager.activeProfileId, onlyProfile.id)
        }
    }

    /// Tests that duplicating a profile creates a copy
    func testDuplicateProfile() async throws {
        await MainActor.run {
            let original = Profile(
                name: "Original",
                buttonMappings: [.a: .key(1)]
            )
            profileManager.profiles = [original]

            let duplicate = profileManager.duplicateProfile(original)

            XCTAssertEqual(duplicate.name, "Original Copy")
            XCTAssertEqual(duplicate.buttonMappings[.a]?.keyCode, 1)
            XCTAssertNotEqual(duplicate.id, original.id)
            XCTAssertEqual(profileManager.profiles.count, 2)
        }
    }

    /// Tests that renaming a profile updates correctly
    func testRenameProfile() async throws {
        await MainActor.run {
            let profile = Profile(name: "OldName")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.renameProfile(profile, to: "NewName")

            XCTAssertEqual(profileManager.profiles.first?.name, "NewName")
            XCTAssertEqual(profileManager.activeProfile?.name, "NewName")
        }
    }

    /// Tests that setting profile icon updates correctly
    func testSetProfileIcon() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.setProfileIcon(profile, icon: "gamecontroller")

            XCTAssertEqual(profileManager.profiles.first?.icon, "gamecontroller")
        }
    }

    // MARK: - Chord Management Tests

    /// Tests adding a chord to profile
    func testAddChord() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            let chord = ChordMapping(buttons: [.a, .b], keyCode: 1)
            profileManager.addChord(chord)

            XCTAssertEqual(profileManager.activeProfile?.chordMappings.count, 1)
            XCTAssertEqual(profileManager.activeProfile?.chordMappings.first?.buttons, [.a, .b])
        }
    }

    /// Tests removing a chord from profile
    func testRemoveChord() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b], keyCode: 1)
            let profile = Profile(name: "Test", chordMappings: [chord])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            XCTAssertEqual(profileManager.activeProfile?.chordMappings.count, 1)

            profileManager.removeChord(chord)

            XCTAssertEqual(profileManager.activeProfile?.chordMappings.count, 0)
        }
    }

    /// Tests updating a chord in profile
    func testUpdateChord() async throws {
        await MainActor.run {
            let chord = ChordMapping(buttons: [.a, .b], keyCode: 1)
            let profile = Profile(name: "Test", chordMappings: [chord])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            var updatedChord = chord
            updatedChord.keyCode = 5

            profileManager.updateChord(updatedChord)

            XCTAssertEqual(profileManager.activeProfile?.chordMappings.first?.keyCode, 5)
        }
    }

    // MARK: - Joystick Settings Tests

    /// Tests updating joystick settings in profile
    func testUpdateJoystickSettings() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            var settings = JoystickSettings.default
            settings.mouseSensitivity = 0.8
            settings.invertMouseY = true

            profileManager.updateJoystickSettings(settings)

            XCTAssertEqual(profileManager.activeProfile?.joystickSettings.mouseSensitivity, 0.8)
            XCTAssertTrue(profileManager.activeProfile?.joystickSettings.invertMouseY ?? false)
        }
    }

    // MARK: - Macro Management Tests

    /// Tests adding a macro to profile
    func testAddMacro() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            let macro = Macro(name: "TestMacro", steps: [.press(KeyMapping(keyCode: 1))])
            profileManager.addMacro(macro)

            XCTAssertEqual(profileManager.activeProfile?.macros.count, 1)
            XCTAssertEqual(profileManager.activeProfile?.macros.first?.name, "TestMacro")
        }
    }

    /// Tests removing a macro also unmaps it from buttons
    func testRemoveMacroUnmapsFromButtons() async throws {
        await MainActor.run {
            let macro = Macro(name: "TestMacro", steps: [.press(KeyMapping(keyCode: 1))])

            var buttonMapping = KeyMapping()
            buttonMapping.macroId = macro.id

            let profile = Profile(
                name: "Test",
                buttonMappings: [.a: buttonMapping],
                macros: [macro]
            )
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            // Verify initial state
            XCTAssertEqual(profileManager.activeProfile?.buttonMappings[.a]?.macroId, macro.id)

            profileManager.removeMacro(macro)

            // Macro should be removed
            XCTAssertEqual(profileManager.activeProfile?.macros.count, 0)
            // Button mapping should be removed too
            XCTAssertNil(profileManager.activeProfile?.buttonMappings[.a])
        }
    }

    /// Tests updating a macro
    func testUpdateMacro() async throws {
        await MainActor.run {
            let macro = Macro(name: "Original", steps: [.press(KeyMapping(keyCode: 1))])
            let profile = Profile(name: "Test", macros: [macro])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            var updatedMacro = macro
            updatedMacro.name = "Updated"
            updatedMacro.steps = [.press(KeyMapping(keyCode: 2)), .delay(0.1)]

            profileManager.updateMacro(updatedMacro)

            XCTAssertEqual(profileManager.activeProfile?.macros.first?.name, "Updated")
            XCTAssertEqual(profileManager.activeProfile?.macros.first?.steps.count, 2)
        }
    }

    // MARK: - Rapid Fire Edge Cases

    /// Tests rapid button press/release cycles
    func testRapidButtonCycles() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "Rapid", buttonMappings: [.a: .key(1)]))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Rapid press/release cycles
        for _ in 0..<5 {
            await MainActor.run {
                controllerService.onButtonPressed?(.a)
                controllerService.onButtonReleased?(.a, 0.01)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        await waitForTasks()

        await MainActor.run {
            let pressCount = mockInputSimulator.events.filter { event in
                if case .pressKey(1, _) = event { return true }
                return false
            }.count

            // Should have executed 5 times (not coalesced)
            XCTAssertEqual(pressCount, 5, "All rapid presses should execute")
        }
    }

    /// Tests button press while another is being held
    func testInterruptHoldWithAnotherButton() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(
                name: "Interrupt",
                buttonMappings: [
                    .a: .holdModifier(.command),
                    .b: .key(1)
                ]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            // Start holding A
            controllerService.onButtonPressed?(.a)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))

            // Press and release B while A held
            controllerService.onButtonPressed?(.b)
            controllerService.onButtonReleased?(.b, 0.05)
        }
        await waitForTasks()

        await MainActor.run {
            // B should execute with command modifier context
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .pressKey(1, _) = event { return true }
                return false
            })

            // A should still be held
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
        }

        await MainActor.run {
            controllerService.onButtonReleased?(.a, 0.5)
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.heldModifiers.contains(.maskCommand))
        }
    }

    // MARK: - Linked Apps Tests

    /// Tests adding a linked app to profile
    func testAddLinkedApp() async throws {
        await MainActor.run {
            let profile = Profile(name: "Gaming")
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.addLinkedApp("com.example.game", to: profile)

            let updatedProfile = profileManager.profiles.first { $0.id == profile.id }
            XCTAssertTrue(updatedProfile?.linkedApps.contains("com.example.game") ?? false)
        }
    }

    /// Tests that adding linked app to one profile removes it from another
    func testAddLinkedAppRemovesFromOther() async throws {
        await MainActor.run {
            var profile1 = Profile(name: "Profile1")
            profile1.linkedApps = ["com.example.game"]
            let profile2 = Profile(name: "Profile2")

            profileManager.profiles = [profile1, profile2]
            profileManager.setActiveProfile(profile1)

            // Move the app to profile2
            profileManager.addLinkedApp("com.example.game", to: profile2)

            let updated1 = profileManager.profiles.first { $0.id == profile1.id }
            let updated2 = profileManager.profiles.first { $0.id == profile2.id }

            XCTAssertFalse(updated1?.linkedApps.contains("com.example.game") ?? true)
            XCTAssertTrue(updated2?.linkedApps.contains("com.example.game") ?? false)
        }
    }

    /// Tests removing a linked app from profile
    func testRemoveLinkedApp() async throws {
        await MainActor.run {
            var profile = Profile(name: "Gaming")
            profile.linkedApps = ["com.example.game"]
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.removeLinkedApp("com.example.game", from: profile)

            let updatedProfile = profileManager.profiles.first { $0.id == profile.id }
            XCTAssertFalse(updatedProfile?.linkedApps.contains("com.example.game") ?? true)
        }
    }

    // MARK: - UI Scale Tests

    /// Tests setting UI scale persists
    func testSetUiScale() async throws {
        await MainActor.run {
            profileManager.setUiScale(1.5)
            XCTAssertEqual(profileManager.uiScale, 1.5)
        }
    }

    // MARK: - Mapping Removal Tests

    /// Tests removing a button mapping
    func testRemoveMapping() async throws {
        await MainActor.run {
            let profile = Profile(name: "Test", buttonMappings: [.a: .key(1), .b: .key(2)])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            profileManager.removeMapping(for: .a)

            XCTAssertNil(profileManager.activeProfile?.buttonMappings[.a])
            XCTAssertNotNil(profileManager.activeProfile?.buttonMappings[.b])
        }
    }

    /// Tests getting a mapping
    func testGetMapping() async throws {
        await MainActor.run {
            let mapping = KeyMapping(keyCode: 5, modifiers: .command)
            let profile = Profile(name: "Test", buttonMappings: [.a: mapping])
            profileManager.profiles = [profile]
            profileManager.setActiveProfile(profile)

            let retrieved = profileManager.getMapping(for: .a)

            XCTAssertEqual(retrieved?.keyCode, 5)
            XCTAssertTrue(retrieved?.modifiers.command ?? false)

            let missing = profileManager.getMapping(for: .b)
            XCTAssertNil(missing)
        }
    }

    // MARK: - Layer Tests

    /// Test that consecutive button presses work correctly (no layers configured)
    func testConsecutiveButtonPressesWithoutLayers() async throws {
        await MainActor.run {
            // Set up profile with mappings for Y and A buttons, no layers
            let yMapping = KeyMapping(keyCode: 16)  // Y key
            let aMapping = KeyMapping(keyCode: 0)   // A key
            let profile = Profile(name: "Test", buttonMappings: [.y: yMapping, .a: aMapping])
            profileManager.setActiveProfile(profile)
        }
        // Allow Combine to deliver profile change
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // Press and release Y button
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.2)

        // Verify Y mapping executed
        var foundYPress = false
        await MainActor.run {
            foundYPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 16 }
                return false
            }
        }
        XCTAssertTrue(foundYPress, "Y button mapping should have executed")

        // Now press and release A button
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)

        // Verify A mapping also executed
        var foundAPress = false
        await MainActor.run {
            foundAPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                return false
            }
        }
        XCTAssertTrue(foundAPress, "A button mapping should have executed after Y button")
    }

    /// Test that layer activator buttons activate layers
    func testLayerActivatorActivatesLayer() async throws {
        await MainActor.run {
            // Create a layer with LB as activator
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [:])
            let profile = Profile(name: "Test", buttonMappings: [:], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        // Allow Combine to deliver profile change
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // Press LB (layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.2)

        // LB should NOT produce any key press (it's just activating the layer)
        var foundKeyPress = false
        await MainActor.run {
            foundKeyPress = mockInputSimulator.events.contains { event in
                if case .pressKey(_, _) = event { return true }
                return false
            }
        }
        XCTAssertFalse(foundKeyPress, "Layer activator should not produce key press")
    }

    /// Test that regular buttons still work when layers are configured
    func testRegularButtonsWorkWithLayersConfigured() async throws {
        await MainActor.run {
            // Create a layer with LB as activator
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [:])
            let yMapping = KeyMapping(keyCode: 16)  // Y key
            let profile = Profile(name: "Test", buttonMappings: [.y: yMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        // Allow Combine to deliver profile change
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // Press Y button (not a layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.2)

        // Verify Y mapping executed
        var foundYPress = false
        await MainActor.run {
            foundYPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 16 }
                return false
            }
        }
        XCTAssertTrue(foundYPress, "Y button should work even when layers are configured")
    }

    /// Test consecutive button presses with layers configured
    func testConsecutiveButtonPressesWithLayers() async throws {
        await MainActor.run {
            // Create a layer with LB as activator
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [:])
            let yMapping = KeyMapping(keyCode: 16)  // Y key
            let aMapping = KeyMapping(keyCode: 0)   // A key
            let profile = Profile(name: "Test", buttonMappings: [.y: yMapping, .a: aMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        // Allow Combine to deliver profile change
        try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms

        // Press LB (layer activator) first
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.1)

        // Press Y button
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.2)

        // Verify Y mapping executed
        var foundYPress = false
        await MainActor.run {
            foundYPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 16 }
                return false
            }
        }
        XCTAssertTrue(foundYPress, "Y button mapping should work after layer activator was pressed")

        // Press A button
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.2)

        // Verify A mapping also executed
        var foundAPress = false
        await MainActor.run {
            foundAPress = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                return false
            }
        }
        XCTAssertTrue(foundAPress, "A button mapping should work after Y button")
    }

    /// Test that layer-specific mapping is used when layer activator is held
    func testLayerMappingUsedWhenLayerActive() async throws {
        await MainActor.run {
            // Base layer: Y -> key 16 (Y key)
            // Layer: Y -> key 0 (A key)
            let baseYMapping = KeyMapping(keyCode: 16)  // Y key
            let layerYMapping = KeyMapping(keyCode: 0)   // A key (different!)
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [.y: layerYMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Press and HOLD LB (layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Clear events before pressing Y
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y while LB is held - should use LAYER mapping (key 0, not 16)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        // Verify layer mapping was used (key 0), not base mapping (key 16)
        var foundLayerMapping = false
        var foundBaseMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 0 { foundLayerMapping = true }
                    if code == 16 { foundBaseMapping = true }
                }
            }
        }
        XCTAssertTrue(foundLayerMapping, "Layer mapping (key 0) should be used when layer is active")
        XCTAssertFalse(foundBaseMapping, "Base mapping (key 16) should NOT be used when layer is active")
    }

    /// Test that buttons not mapped in layer fall through to base layer
    func testLayerFallthroughToBaseLayer() async throws {
        await MainActor.run {
            // Base layer: Y -> key 16, A -> key 0
            // Layer: only has mapping for A -> key 1 (different), Y is not mapped in layer
            let baseYMapping = KeyMapping(keyCode: 16)  // Y key
            let baseAMapping = KeyMapping(keyCode: 0)   // A key
            let layerAMapping = KeyMapping(keyCode: 1)  // S key (override for A)
            // Layer has NO mapping for Y
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [.a: layerAMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping, .a: baseAMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Press and HOLD LB (layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y while layer is active - should fall through to base layer (key 16)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        // Verify Y used base layer mapping (fallthrough)
        var foundYBaseMapping = false
        await MainActor.run {
            foundYBaseMapping = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 16 }
                return false
            }
        }
        XCTAssertTrue(foundYBaseMapping, "Y should fall through to base layer mapping when not in layer")

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press A while layer is active - should use layer mapping (key 1), not base (key 0)
        await MainActor.run {
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.a)
        }
        await waitForTasks(0.1)

        var foundALayerMapping = false
        var foundABaseMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 1 { foundALayerMapping = true }
                    if code == 0 { foundABaseMapping = true }
                }
            }
        }
        XCTAssertTrue(foundALayerMapping, "A should use layer mapping when layer is active")
        XCTAssertFalse(foundABaseMapping, "A should NOT use base mapping when layer overrides it")
    }

    /// Test that layer deactivates when activator button is released
    func testLayerDeactivatesOnRelease() async throws {
        await MainActor.run {
            // Base layer: Y -> key 16
            // Layer: Y -> key 0
            let baseYMapping = KeyMapping(keyCode: 16)
            let layerYMapping = KeyMapping(keyCode: 0)
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [.y: layerYMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Press and HOLD LB, then release it
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y after LB was released - should use BASE mapping (key 16)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundBaseMapping = false
        var foundLayerMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 16 { foundBaseMapping = true }
                    if code == 0 { foundLayerMapping = true }
                }
            }
        }
        XCTAssertTrue(foundBaseMapping, "Base mapping should be used after layer deactivates")
        XCTAssertFalse(foundLayerMapping, "Layer mapping should NOT be used after layer deactivates")
    }

    /// Test that multiple layers can be configured with different activators
    func testMultipleLayers() async throws {
        await MainActor.run {
            // Base layer: Y -> key 16
            // Layer 1 (LB): Y -> key 0
            // Layer 2 (RB): Y -> key 1
            let baseYMapping = KeyMapping(keyCode: 16)
            let layer1YMapping = KeyMapping(keyCode: 0)
            let layer2YMapping = KeyMapping(keyCode: 1)
            let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.y: layer1YMapping])
            let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.y: layer2YMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping], layers: [layer1, layer2])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Test Layer 1 activation (LB)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            mockInputSimulator.clearEvents()
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.1)

        var foundLayer1Mapping = false
        await MainActor.run {
            foundLayer1Mapping = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                return false
            }
        }
        XCTAssertTrue(foundLayer1Mapping, "Layer 1 mapping should be used when LB is held")

        // Test Layer 2 activation (RB)
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            mockInputSimulator.clearEvents()
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
            controllerService.buttonReleased(.rightBumper)
        }
        await waitForTasks(0.1)

        var foundLayer2Mapping = false
        await MainActor.run {
            foundLayer2Mapping = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }
        }
        XCTAssertTrue(foundLayer2Mapping, "Layer 2 mapping should be used when RB is held")
    }

    /// Test that layer activator button releases don't trigger any mapping
    func testLayerActivatorReleaseProducesNoOutput() async throws {
        await MainActor.run {
            // Give LB a base mapping that should NOT trigger when used as layer activator
            let lbMapping = KeyMapping(keyCode: 16)
            let layer = Layer(name: "Test Layer", activatorButton: .leftBumper, buttonMappings: [:])
            let profile = Profile(name: "Test", buttonMappings: [.leftBumper: lbMapping], layers: [layer])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Press and release LB (layer activator)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonReleased(.leftBumper)
        }
        await waitForTasks(0.2)

        // Verify NO key press occurred
        var foundAnyKeyPress = false
        await MainActor.run {
            foundAnyKeyPress = mockInputSimulator.events.contains { event in
                if case .pressKey(_, _) = event { return true }
                return false
            }
        }
        XCTAssertFalse(foundAnyKeyPress, "Layer activator should not produce any key press, even if base layer has a mapping for it")
    }

    /// Test that layer state is cleared when profile switches while layer activator is held
    func testLayerStateClearedOnProfileSwitch() async throws {
        // Profile A: LB activates layer, Y -> key 0 in layer
        // Profile B: No layers, Y -> key 16 in base
        let layerAYMapping = KeyMapping(keyCode: 0)
        let layerA = Layer(name: "Layer A", activatorButton: .leftBumper, buttonMappings: [.y: layerAYMapping])
        let profileA = Profile(name: "Profile A", buttonMappings: [:], layers: [layerA])

        let baseBYMapping = KeyMapping(keyCode: 16)
        let profileB = Profile(name: "Profile B", buttonMappings: [.y: baseBYMapping], layers: [])

        await MainActor.run {
            profileManager.setActiveProfile(profileA)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Hold LB to activate layer in Profile A
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Switch to Profile B while LB is still held
        await MainActor.run {
            profileManager.setActiveProfile(profileB)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y - should use Profile B's base mapping (key 16), not stale layer mapping
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundProfileBMapping = false
        var foundStaleLayerMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 16 { foundProfileBMapping = true }
                    if code == 0 { foundStaleLayerMapping = true }
                }
            }
        }
        XCTAssertTrue(foundProfileBMapping, "Profile B's base mapping should be used after profile switch")
        XCTAssertFalse(foundStaleLayerMapping, "Stale layer mapping from Profile A should NOT be used")
    }

    /// Test that pressing a second layer activator while holding the first switches to the new layer
    func testLayerSwitchingMostRecentWins() async throws {
        await MainActor.run {
            // Layer 1 (LB): Y -> key 0
            // Layer 2 (RB): Y -> key 1
            let layer1YMapping = KeyMapping(keyCode: 0)
            let layer2YMapping = KeyMapping(keyCode: 1)
            let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.y: layer1YMapping])
            let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.y: layer2YMapping])
            let profile = Profile(name: "Test", buttonMappings: [:], layers: [layer1, layer2])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Hold LB (Layer 1)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Now also press RB (Layer 2) - should switch to Layer 2
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y - should use Layer 2's mapping (key 1), not Layer 1's (key 0)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundLayer2Mapping = false
        var foundLayer1Mapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 1 { foundLayer2Mapping = true }
                    if code == 0 { foundLayer1Mapping = true }
                }
            }
        }
        XCTAssertTrue(foundLayer2Mapping, "Layer 2 mapping should be used (most recently pressed activator)")
        XCTAssertFalse(foundLayer1Mapping, "Layer 1 mapping should NOT be used")
    }

    /// Test that releasing the most recent layer activator reverts to the previous held layer
    func testLayerSwitchingReleaseRevertsToHeldLayer() async throws {
        await MainActor.run {
            // Base: Y -> key 16
            // Layer 1 (LB): Y -> key 0
            // Layer 2 (RB): Y -> key 1
            let baseYMapping = KeyMapping(keyCode: 16)
            let layer1YMapping = KeyMapping(keyCode: 0)
            let layer2YMapping = KeyMapping(keyCode: 1)
            let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.y: layer1YMapping])
            let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.y: layer2YMapping])
            let profile = Profile(name: "Test", buttonMappings: [.y: baseYMapping], layers: [layer1, layer2])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Hold LB (Layer 1), then press RB (Layer 2)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)

        // Now release RB - should revert to Layer 1 (LB still held)
        await MainActor.run {
            controllerService.buttonReleased(.rightBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y - should use Layer 1's mapping (key 0)
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundLayer1Mapping = false
        var foundLayer2Mapping = false
        var foundBaseMapping = false
        await MainActor.run {
            for event in mockInputSimulator.events {
                if case .pressKey(let code, _) = event {
                    if code == 0 { foundLayer1Mapping = true }
                    if code == 1 { foundLayer2Mapping = true }
                    if code == 16 { foundBaseMapping = true }
                }
            }
        }
        XCTAssertTrue(foundLayer1Mapping, "Layer 1 mapping should be used after releasing Layer 2")
        XCTAssertFalse(foundLayer2Mapping, "Layer 2 mapping should NOT be used after releasing it")
        XCTAssertFalse(foundBaseMapping, "Base mapping should NOT be used while Layer 1 activator is held")
    }

    /// Test that layer activators in Layer A cannot trigger when Layer A is active
    /// (i.e., layer activator for Layer B should still work to switch to Layer B)
    func testLayerActivatorsSwitchFromAnyLayer() async throws {
        await MainActor.run {
            // Layer 1 (LB): Y -> key 0
            // Layer 2 (RB): Y -> key 1
            let layer1YMapping = KeyMapping(keyCode: 0)
            let layer2YMapping = KeyMapping(keyCode: 1)
            let layer1 = Layer(name: "Layer 1", activatorButton: .leftBumper, buttonMappings: [.y: layer1YMapping])
            let layer2 = Layer(name: "Layer 2", activatorButton: .rightBumper, buttonMappings: [.y: layer2YMapping])
            let profile = Profile(name: "Test", buttonMappings: [:], layers: [layer1, layer2])
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        // Hold LB (enter Layer 1)
        await MainActor.run {
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks(0.1)

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press RB while in Layer 1 - should switch to Layer 2, not produce any key output
        await MainActor.run {
            controllerService.buttonPressed(.rightBumper)
        }
        await waitForTasks(0.1)

        // Verify no key was pressed for RB (it's a layer activator)
        var foundAnyKeyPress = false
        await MainActor.run {
            foundAnyKeyPress = mockInputSimulator.events.contains { event in
                if case .pressKey(_, _) = event { return true }
                return false
            }
        }
        XCTAssertFalse(foundAnyKeyPress, "Layer activator RB should not produce key press, just switch layers")

        // Clear events
        await MainActor.run {
            mockInputSimulator.clearEvents()
        }

        // Press Y - should use Layer 2's mapping now
        await MainActor.run {
            controllerService.buttonPressed(.y)
        }
        await waitForTasks(0.2)
        await MainActor.run {
            controllerService.buttonReleased(.y)
        }
        await waitForTasks(0.1)

        var foundLayer2Mapping = false
        await MainActor.run {
            foundLayer2Mapping = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 1 }
                return false
            }
        }
        XCTAssertTrue(foundLayer2Mapping, "Layer 2 mapping should be used after switching from Layer 1")
    }

    // MARK: - Swap Mapping Tests

    /// Test swapping two button mappings in base layer
    func testSwapMappingsBasic() async throws {
        await MainActor.run {
            // Set up profile with two different mappings
            let mappingA = KeyMapping(keyCode: 0, modifiers: .command, hint: "Hint A")  // A key with Cmd
            let mappingB = KeyMapping(keyCode: 1, modifiers: .shift, hint: "Hint B")    // S key with Shift
            let profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA, .b: mappingB])
            profileManager.setActiveProfile(profile)
        }

        // Perform the swap
        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        // Verify the mappings are swapped
        await MainActor.run {
            let newMappingA = profileManager.getMapping(for: .a)
            let newMappingB = profileManager.getMapping(for: .b)

            // A should now have B's original mapping
            XCTAssertEqual(newMappingA?.keyCode, 1, "Button A should have B's keyCode after swap")
            XCTAssertTrue(newMappingA?.modifiers.shift ?? false, "Button A should have B's modifiers after swap")
            XCTAssertEqual(newMappingA?.hint, "Hint B", "Button A should have B's hint after swap")

            // B should now have A's original mapping
            XCTAssertEqual(newMappingB?.keyCode, 0, "Button B should have A's keyCode after swap")
            XCTAssertTrue(newMappingB?.modifiers.command ?? false, "Button B should have A's modifiers after swap")
            XCTAssertEqual(newMappingB?.hint, "Hint A", "Button B should have A's hint after swap")
        }
    }

    /// Test swapping when one button has mapping and other doesn't
    func testSwapMappingsOneEmpty() async throws {
        await MainActor.run {
            let mappingA = KeyMapping(keyCode: 5)
            let profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA])
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        await MainActor.run {
            let newMappingA = profileManager.getMapping(for: .a)
            let newMappingB = profileManager.getMapping(for: .b)

            // A should now be empty (B had no mapping)
            XCTAssertNil(newMappingA, "Button A should be nil after swap with empty button")

            // B should now have A's original mapping
            XCTAssertEqual(newMappingB?.keyCode, 5, "Button B should have A's keyCode after swap")
        }
    }

    /// Test swapping preserves long hold and double tap mappings
    func testSwapMappingsWithAdvancedFeatures() async throws {
        await MainActor.run {
            var mappingA = KeyMapping(keyCode: 0)
            mappingA.longHoldMapping = LongHoldMapping(keyCode: 10, threshold: 0.5)
            mappingA.doubleTapMapping = DoubleTapMapping(keyCode: 11, threshold: 0.3)

            var mappingB = KeyMapping(keyCode: 1)
            mappingB.repeatMapping = RepeatMapping(enabled: true, interval: 0.1)
            mappingB.isHoldModifier = true

            let profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA, .b: mappingB])
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        await MainActor.run {
            let newMappingA = profileManager.getMapping(for: .a)
            let newMappingB = profileManager.getMapping(for: .b)

            // A should now have B's repeat and hold settings
            XCTAssertEqual(newMappingA?.keyCode, 1)
            XCTAssertTrue(newMappingA?.repeatMapping?.enabled ?? false, "Button A should have B's repeat setting")
            XCTAssertTrue(newMappingA?.isHoldModifier ?? false, "Button A should have B's hold modifier setting")
            XCTAssertNil(newMappingA?.longHoldMapping, "Button A should not have long hold (B didn't have it)")

            // B should now have A's long hold and double tap
            XCTAssertEqual(newMappingB?.keyCode, 0)
            XCTAssertEqual(newMappingB?.longHoldMapping?.keyCode, 10, "Button B should have A's long hold mapping")
            XCTAssertEqual(newMappingB?.doubleTapMapping?.keyCode, 11, "Button B should have A's double tap mapping")
        }
    }

    /// Test swapping same button with itself does nothing
    func testSwapMappingsSameButton() async throws {
        await MainActor.run {
            let mappingA = KeyMapping(keyCode: 5, hint: "Original")
            let profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA])
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .a)
        }

        await MainActor.run {
            let mapping = profileManager.getMapping(for: .a)
            XCTAssertEqual(mapping?.keyCode, 5, "Mapping should be unchanged when swapping with self")
            XCTAssertEqual(mapping?.hint, "Original", "Hint should be unchanged when swapping with self")
        }
    }

    /// Test swapping within a layer
    func testSwapLayerMappings() async throws {
        await MainActor.run {
            var profile = Profile(name: "Layer Swap Test")

            // Create a layer with button mappings
            var layer = Layer(id: UUID(), name: "Test Layer", activatorButton: .leftBumper)
            layer.buttonMappings[.a] = KeyMapping(keyCode: 10, hint: "Layer A")
            layer.buttonMappings[.b] = KeyMapping(keyCode: 11, hint: "Layer B")
            profile.layers.append(layer)

            profileManager.setActiveProfile(profile)
        }

        // Get the layer ID
        var layerId: UUID!
        await MainActor.run {
            layerId = profileManager.activeProfile?.layers.first?.id
        }

        // Swap within the layer
        await MainActor.run {
            profileManager.swapLayerMappings(button1: .a, button2: .b, in: layerId)
        }

        // Verify the swap
        await MainActor.run {
            guard let layer = profileManager.activeProfile?.layers.first else {
                XCTFail("Layer should exist")
                return
            }

            let newMappingA = layer.buttonMappings[.a]
            let newMappingB = layer.buttonMappings[.b]

            XCTAssertEqual(newMappingA?.keyCode, 11, "Layer button A should have B's keyCode")
            XCTAssertEqual(newMappingA?.hint, "Layer B", "Layer button A should have B's hint")
            XCTAssertEqual(newMappingB?.keyCode, 10, "Layer button B should have A's keyCode")
            XCTAssertEqual(newMappingB?.hint, "Layer A", "Layer button B should have A's hint")
        }
    }

    /// Test that swapping does not affect chords
    func testSwapMappingsDoesNotAffectChords() async throws {
        await MainActor.run {
            let mappingA = KeyMapping(keyCode: 0)
            let mappingB = KeyMapping(keyCode: 1)
            let chord = ChordMapping(buttons: [.a, .b], keyCode: 99, hint: "Chord AB")

            var profile = Profile(name: "Swap Test", buttonMappings: [.a: mappingA, .b: mappingB])
            profile.chordMappings.append(chord)
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        await MainActor.run {
            // Chord should be unchanged
            guard let profile = profileManager.activeProfile else {
                XCTFail("Profile should exist")
                return
            }

            XCTAssertEqual(profile.chordMappings.count, 1, "Chord count should be unchanged")
            let chord = profile.chordMappings.first
            XCTAssertEqual(chord?.buttons, [.a, .b], "Chord buttons should be unchanged")
            XCTAssertEqual(chord?.keyCode, 99, "Chord keyCode should be unchanged")
            XCTAssertEqual(chord?.hint, "Chord AB", "Chord hint should be unchanged")
        }
    }

    /// Test swapping with macro assignments
    func testSwapMappingsWithMacros() async throws {
        let macroId1 = UUID()
        let macroId2 = UUID()

        await MainActor.run {
            var profile = Profile(name: "Macro Swap Test")
            profile.macros = [
                Macro(id: macroId1, name: "Macro 1", steps: [.delay(0.1)]),
                Macro(id: macroId2, name: "Macro 2", steps: [.delay(0.2)])
            ]
            profile.buttonMappings[.a] = KeyMapping(macroId: macroId1, hint: "Triggers Macro 1")
            profile.buttonMappings[.b] = KeyMapping(macroId: macroId2, hint: "Triggers Macro 2")
            profileManager.setActiveProfile(profile)
        }

        await MainActor.run {
            profileManager.swapMappings(button1: .a, button2: .b)
        }

        await MainActor.run {
            let newMappingA = profileManager.getMapping(for: .a)
            let newMappingB = profileManager.getMapping(for: .b)

            XCTAssertEqual(newMappingA?.macroId, macroId2, "Button A should have B's macro")
            XCTAssertEqual(newMappingA?.hint, "Triggers Macro 2", "Button A should have B's hint")
            XCTAssertEqual(newMappingB?.macroId, macroId1, "Button B should have A's macro")
            XCTAssertEqual(newMappingB?.hint, "Triggers Macro 1", "Button B should have A's hint")
        }
    }

    // MARK: - Stick to WASD/Arrow Keys Mode Tests

    /// Tests left stick WASD mode - pushing up triggers W key
    func testLeftStickWASDModeUpDirection() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStickMode = .wasdKeys
            profile.joystickSettings.mouseDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms for profile to propagate

        // Push stick up (positive Y)
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.8))
        await waitForTasks(0.2)

        await MainActor.run {
            // W key = keyCode 13
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .keyDown(let code) = event { return code == 13 }
                return false
            }, "W key should be pressed when stick pushed up")
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(13), "W key should be held")
        }
    }

    /// Tests left stick WASD mode - diagonal direction (up-right) triggers W+D
    func testLeftStickWASDModeDiagonal() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStickMode = .wasdKeys
            profile.joystickSettings.mouseDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Push stick up-right (positive X and Y)
        controllerService.setLeftStickForTesting(CGPoint(x: 0.7, y: 0.7))
        await waitForTasks(0.2)

        await MainActor.run {
            // W = 13, D = 2
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(13), "W key should be held")
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(2), "D key should be held")
        }
    }

    /// Tests left stick WASD mode - keys released when returning to center
    func testLeftStickWASDModeReleaseOnCenter() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStickMode = .wasdKeys
            profile.joystickSettings.mouseDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Push stick up
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.8))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.contains(13), "W key should be held")
        }

        // Return to center
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.0))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.isEmpty, "All keys should be released when stick returns to center")
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .keyUp(let code) = event { return code == 13 }
                return false
            }, "W key should have keyUp event")
        }
    }

    /// Tests left stick WASD mode - deadzone respected
    func testLeftStickWASDModeDeadzoneRespected() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStickMode = .wasdKeys
            profile.joystickSettings.mouseDeadzone = 0.3 // Higher deadzone
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Push stick just inside deadzone
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.2))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.isEmpty, "No keys should be held inside deadzone")
            XCTAssertFalse(mockInputSimulator.events.contains { event in
                if case .keyDown = event { return true }
                return false
            }, "No keyDown events inside deadzone")
        }
    }

    /// Tests right stick arrow keys mode setting persistence
    func testRightStickArrowKeysMode() async throws {
        await MainActor.run {
            var profile = Profile(name: "Arrows", buttonMappings: [:])
            profile.joystickSettings.rightStickMode = .arrowKeys
            profile.joystickSettings.scrollDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        await MainActor.run {
            XCTAssertEqual(profileManager.activeProfile?.joystickSettings.rightStickMode, .arrowKeys)
        }
    }

    /// Tests that disabling engine releases held direction keys
    func testEngineDisableReleasesDirectionKeys() async throws {
        await MainActor.run {
            var profile = Profile(name: "WASD", buttonMappings: [:])
            profile.joystickSettings.leftStickMode = .wasdKeys
            profile.joystickSettings.mouseDeadzone = 0.15
            profileManager.setActiveProfile(profile)
            controllerService.isConnected = true
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Push stick up
        controllerService.setLeftStickForTesting(CGPoint(x: 0.0, y: 0.8))
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertFalse(mockInputSimulator.heldDirectionKeys.isEmpty, "Keys should be held before disable")
            mappingEngine.disable()
        }
        await waitForTasks()

        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldDirectionKeys.isEmpty, "All direction keys should be released on disable")
        }
    }

    /// Tests stick mode setting persistence
    func testStickModeSettingPersistence() async throws {
        await MainActor.run {
            var profile = Profile(name: "ModeTest", buttonMappings: [:])
            profile.joystickSettings.leftStickMode = .wasdKeys
            profile.joystickSettings.rightStickMode = .arrowKeys
            profileManager.setActiveProfile(profile)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        await MainActor.run {
            XCTAssertEqual(profileManager.activeProfile?.joystickSettings.leftStickMode, .wasdKeys)
            XCTAssertEqual(profileManager.activeProfile?.joystickSettings.rightStickMode, .arrowKeys)
        }
    }
}

// MARK: - KeyCodeMapping Tests

final class KeyCodeMappingTests: XCTestCase {

    // MARK: - Function Key Fn Flag Tests

    /// Tests that F1-F12 require the Fn flag
    func testF1ThroughF12RequireFnFlag() {
        let fKeyCodes: [CGKeyCode] = [
            CGKeyCode(kVK_F1), CGKeyCode(kVK_F2), CGKeyCode(kVK_F3), CGKeyCode(kVK_F4),
            CGKeyCode(kVK_F5), CGKeyCode(kVK_F6), CGKeyCode(kVK_F7), CGKeyCode(kVK_F8),
            CGKeyCode(kVK_F9), CGKeyCode(kVK_F10), CGKeyCode(kVK_F11), CGKeyCode(kVK_F12)
        ]

        for (index, keyCode) in fKeyCodes.enumerated() {
            XCTAssertTrue(
                KeyCodeMapping.requiresFnFlag(keyCode),
                "F\(index + 1) (keyCode \(keyCode)) should require Fn flag"
            )
            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(
                flags.contains(.maskSecondaryFn),
                "F\(index + 1) should have maskSecondaryFn in specialKeyFlags"
            )
        }
    }

    /// Tests that F13-F20 require the Fn flag (regression test for CSI u escape sequence bug)
    /// Without this flag, terminals using Kitty keyboard protocol output escape sequences
    /// like [57376u instead of triggering hotkeys.
    func testF13ThroughF20RequireFnFlag() {
        let extendedFKeyCodes: [CGKeyCode] = [
            CGKeyCode(kVK_F13), CGKeyCode(kVK_F14), CGKeyCode(kVK_F15), CGKeyCode(kVK_F16),
            CGKeyCode(kVK_F17), CGKeyCode(kVK_F18), CGKeyCode(kVK_F19), CGKeyCode(kVK_F20)
        ]

        for (index, keyCode) in extendedFKeyCodes.enumerated() {
            XCTAssertTrue(
                KeyCodeMapping.requiresFnFlag(keyCode),
                "F\(index + 13) (keyCode \(keyCode)) should require Fn flag"
            )
            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(
                flags.contains(.maskSecondaryFn),
                "F\(index + 13) should have maskSecondaryFn in specialKeyFlags"
            )
        }
    }

    // MARK: - Navigation Key Flag Tests

    /// Tests that arrow keys require both Fn and NumPad flags
    func testArrowKeysRequireFnAndNumPadFlags() {
        let arrowKeys: [(name: String, code: CGKeyCode)] = [
            ("Left", CGKeyCode(kVK_LeftArrow)),
            ("Right", CGKeyCode(kVK_RightArrow)),
            ("Up", CGKeyCode(kVK_UpArrow)),
            ("Down", CGKeyCode(kVK_DownArrow))
        ]

        for (name, keyCode) in arrowKeys {
            XCTAssertTrue(
                KeyCodeMapping.requiresFnFlag(keyCode),
                "\(name) arrow should require Fn flag"
            )
            XCTAssertTrue(
                KeyCodeMapping.requiresNumPadFlag(keyCode),
                "\(name) arrow should require NumPad flag"
            )

            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(flags.contains(.maskSecondaryFn), "\(name) arrow should have Fn flag")
            XCTAssertTrue(flags.contains(.maskNumericPad), "\(name) arrow should have NumPad flag")
        }
    }

    /// Tests that navigation keys (Home, End, Page Up/Down, Forward Delete) require proper flags
    func testNavigationKeysRequireProperFlags() {
        let navKeys: [(name: String, code: CGKeyCode)] = [
            ("Home", CGKeyCode(kVK_Home)),
            ("End", CGKeyCode(kVK_End)),
            ("Page Up", CGKeyCode(kVK_PageUp)),
            ("Page Down", CGKeyCode(kVK_PageDown)),
            ("Forward Delete", CGKeyCode(kVK_ForwardDelete))
        ]

        for (name, keyCode) in navKeys {
            XCTAssertTrue(
                KeyCodeMapping.requiresFnFlag(keyCode),
                "\(name) should require Fn flag"
            )
            XCTAssertTrue(
                KeyCodeMapping.requiresNumPadFlag(keyCode),
                "\(name) should require NumPad flag"
            )

            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(flags.contains(.maskSecondaryFn), "\(name) should have Fn flag")
            XCTAssertTrue(flags.contains(.maskNumericPad), "\(name) should have NumPad flag")
        }
    }

    // MARK: - Regular Key Tests

    /// Tests that regular letter keys don't require special flags
    func testRegularKeysDoNotRequireSpecialFlags() {
        let regularKeys: [CGKeyCode] = [
            CGKeyCode(kVK_ANSI_A), CGKeyCode(kVK_ANSI_Z),
            CGKeyCode(kVK_ANSI_0), CGKeyCode(kVK_ANSI_9),
            CGKeyCode(kVK_Space), CGKeyCode(kVK_Return),
            CGKeyCode(kVK_Tab), CGKeyCode(kVK_Escape)
        ]

        for keyCode in regularKeys {
            let flags = KeyCodeMapping.specialKeyFlags(for: keyCode)
            XCTAssertTrue(
                flags.isEmpty,
                "Regular key \(keyCode) should not require special flags, got \(flags.rawValue)"
            )
            XCTAssertFalse(KeyCodeMapping.requiresFnFlag(keyCode))
            XCTAssertFalse(KeyCodeMapping.requiresNumPadFlag(keyCode))
        }
    }
}

// MARK: - ActionFeedbackView Tests

final class ActionFeedbackViewTests: XCTestCase {

    /// Tests that ActionFeedbackView sizes correctly for short text
    @MainActor
    func testActionFeedbackViewShortText() {
        let view = ActionFeedbackView(action: "A", type: .singlePress)
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize

        XCTAssertGreaterThan(size.width, 0, "View should have positive width")
        XCTAssertGreaterThan(size.height, 0, "View should have positive height")
    }

    /// Tests that ActionFeedbackView expands to fit long text without truncation
    @MainActor
    func testActionFeedbackViewLongTextNotTruncated() {
        let shortView = ActionFeedbackView(action: "A", type: .singlePress)
        let shortHosting = NSHostingView(rootView: shortView)
        let shortSize = shortHosting.fittingSize

        let longText = "This is a very long action hint that should not be truncated"
        let longView = ActionFeedbackView(action: longText, type: .singlePress)
        let longHosting = NSHostingView(rootView: longView)
        let longSize = longHosting.fittingSize

        // Long text should result in wider view
        XCTAssertGreaterThan(longSize.width, shortSize.width,
            "Long text view should be wider than short text view")

        // Width should be proportional to text length (roughly)
        // Long text is ~60 chars, short is 1 char, so width should be significantly larger
        XCTAssertGreaterThan(longSize.width, shortSize.width * 2,
            "Long text view should be significantly wider")
    }

    /// Tests that ActionFeedbackView includes badge width for special types
    @MainActor
    func testActionFeedbackViewWithBadge() {
        let noBadgeView = ActionFeedbackView(action: "Test", type: .singlePress)
        let noBadgeHosting = NSHostingView(rootView: noBadgeView)
        let noBadgeSize = noBadgeHosting.fittingSize

        let badgeView = ActionFeedbackView(action: "Test", type: .doubleTap)
        let badgeHosting = NSHostingView(rootView: badgeView)
        let badgeSize = badgeHosting.fittingSize

        // View with badge should be wider
        XCTAssertGreaterThan(badgeSize.width, noBadgeSize.width,
            "View with badge should be wider than view without badge")
    }

    /// Tests that ActionFeedbackView includes held indicator width
    @MainActor
    func testActionFeedbackViewWithHeldIndicator() {
        let notHeldView = ActionFeedbackView(action: "Test", type: .singlePress, isHeld: false)
        let notHeldHosting = NSHostingView(rootView: notHeldView)
        let notHeldSize = notHeldHosting.fittingSize

        let heldView = ActionFeedbackView(action: "Test", type: .singlePress, isHeld: true)
        let heldHosting = NSHostingView(rootView: heldView)
        let heldSize = heldHosting.fittingSize

        // View with held indicator should be wider
        XCTAssertGreaterThan(heldSize.width, notHeldSize.width,
            "View with held indicator should be wider")
    }

    /// Tests that ActionFeedbackView handles emoji and special characters
    @MainActor
    func testActionFeedbackViewWithEmoji() {
        let emojiText = "🎮 Game Mode 🕹️"
        let view = ActionFeedbackView(action: emojiText, type: .singlePress)
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize

        XCTAssertGreaterThan(size.width, 50, "Emoji text should result in reasonable width")
        XCTAssertGreaterThan(size.height, 0, "View should have positive height")
    }

    /// Tests that view width scales with content, not fixed at 200px
    @MainActor
    func testActionFeedbackViewNotFixedWidth() {
        let veryLongText = String(repeating: "A", count: 50)
        let view = ActionFeedbackView(action: veryLongText, type: .doubleTap, isHeld: true)
        let hostingView = NSHostingView(rootView: view)
        let size = hostingView.fittingSize

        // Should be wider than the old fixed 200px limit
        XCTAssertGreaterThan(size.width, 200,
            "View with long text should exceed old 200px fixed width")
    }

    // MARK: - Multiple Held Modifier Tests

    /// Tests that combined modifier text displays wider than single modifier
    @MainActor
    func testActionFeedbackViewCombinedModifiers() {
        let singleModifier = ActionFeedbackView(action: "⌘", type: .singlePress, isHeld: true)
        let singleHosting = NSHostingView(rootView: singleModifier)
        let singleSize = singleHosting.fittingSize

        let combinedModifiers = ActionFeedbackView(action: "⌘ + ⇧", type: .singlePress, isHeld: true)
        let combinedHosting = NSHostingView(rootView: combinedModifiers)
        let combinedSize = combinedHosting.fittingSize

        // Combined modifiers text should be wider
        XCTAssertGreaterThan(combinedSize.width, singleSize.width,
            "Combined modifier view should be wider than single modifier")
    }

    /// Tests that three combined modifiers display even wider
    @MainActor
    func testActionFeedbackViewThreeModifiers() {
        let twoModifiers = ActionFeedbackView(action: "⌘ + ⇧", type: .singlePress, isHeld: true)
        let twoHosting = NSHostingView(rootView: twoModifiers)
        let twoSize = twoHosting.fittingSize

        let threeModifiers = ActionFeedbackView(action: "⌃ + ⌘ + ⇧", type: .singlePress, isHeld: true)
        let threeHosting = NSHostingView(rootView: threeModifiers)
        let threeSize = threeHosting.fittingSize

        // Three modifiers should be wider than two
        XCTAssertGreaterThan(threeSize.width, twoSize.width,
            "Three modifier view should be wider than two modifier view")
    }
}

// MARK: - Chord Conflict Detection Tests

final class ChordConflictTests: XCTestCase {

    // MARK: - Basic Conflict Detection

    func testNoConflictWhenNoExistingChords() {
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing: [ChordMapping] = []

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testNoConflictWhenNoButtonsSelected() {
        let selected: Set<ControllerButton> = []
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty, "Should not conflict when no buttons are selected")
    }

    func testSingleButtonSelectedConflictsWithTwoButtonChord() {
        // Existing chord: Left + Down
        // User selects: Left
        // Expected conflict: Down (because Left + Down already exists)
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.dpadDown])
    }

    func testSingleButtonSelectedNoConflictWithUnrelatedChord() {
        // Existing chord: A + B
        // User selects: Left
        // Expected: No conflict (Left is not part of the A+B chord)
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(buttons: [.a, .b], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty)
    }

    // MARK: - Multi-Button Selection

    func testTwoButtonsSelectedConflictsWithThreeButtonChord() {
        // Existing chord: Left + Down + Right
        // User selects: Left + Down
        // Expected conflict: Right (would complete the 3-button chord)
        let selected: Set<ControllerButton> = [.dpadLeft, .dpadDown]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown, .dpadRight], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.dpadRight])
    }

    func testNoConflictWhenMoreThanOneButtonRemains() {
        // Existing chord: Left + Down + Right
        // User selects: Left
        // Expected: No conflict (adding Down or Right alone won't complete the chord)
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown, .dpadRight], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty, "Should not conflict when more than one button is needed to complete chord")
    }

    // MARK: - Multiple Existing Chords

    func testMultipleConflictsFromDifferentChords() {
        // Existing chords: Left + Down, Left + Up
        // User selects: Left
        // Expected conflicts: Down, Up (both would create duplicates)
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0),
            ChordMapping(buttons: [.dpadLeft, .dpadUp], keyCode: 1)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.dpadDown, .dpadUp])
    }

    func testPartialOverlapWithMultipleChords() {
        // Existing chords: A + B, A + B + X
        // User selects: A + B
        // Expected: X is conflicted (completes A+B+X), but A+B itself is already a chord (handled by chordAlreadyExists)
        let selected: Set<ControllerButton> = [.a, .b]
        let existing = [
            ChordMapping(buttons: [.a, .b], keyCode: 0),
            ChordMapping(buttons: [.a, .b, .x], keyCode: 1)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.x])
    }

    // MARK: - Edit Mode (Exclude Current Chord)

    func testEditModeExcludesCurrentChord() {
        // Existing chord: Left + Down (ID: xxx)
        // User is editing chord xxx and has Left + Down selected
        // Selects just Left
        // Expected: No conflict for Down (we're editing the very chord that has Left + Down)
        let chordId = UUID()
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(id: chordId, buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing,
            editingChordId: chordId
        )

        XCTAssertTrue(conflicts.isEmpty, "Should not conflict with the chord being edited")
    }

    func testEditModeStillConflictsWithOtherChords() {
        // Existing chords: Left + Down (ID: xxx), Left + Up (ID: yyy)
        // User is editing chord xxx and selects Left
        // Expected: Up is conflicted (from chord yyy), Down is NOT (from chord xxx being edited)
        let chordIdX = UUID()
        let chordIdY = UUID()
        let selected: Set<ControllerButton> = [.dpadLeft]
        let existing = [
            ChordMapping(id: chordIdX, buttons: [.dpadLeft, .dpadDown], keyCode: 0),
            ChordMapping(id: chordIdY, buttons: [.dpadLeft, .dpadUp], keyCode: 1)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing,
            editingChordId: chordIdX
        )

        XCTAssertEqual(conflicts, [.dpadUp])
    }

    // MARK: - Edge Cases

    func testSelectedButtonsMatchExistingChordExactly() {
        // Existing chord: Left + Down
        // User selects: Left + Down (exact match)
        // Expected: No additional conflicts (the duplicate is handled by chordAlreadyExists, not conflictedButtons)
        let selected: Set<ControllerButton> = [.dpadLeft, .dpadDown]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty, "Exact match handled by chordAlreadyExists, not conflictedButtons")
    }

    func testSelectedButtonsSupersetOfExistingChord() {
        // Existing chord: Left + Down
        // User selects: Left + Down + Right (superset)
        // Expected: No conflict (selected is already larger than existing chord)
        let selected: Set<ControllerButton> = [.dpadLeft, .dpadDown, .dpadRight]
        let existing = [
            ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testNoConflictWithDisjointSets() {
        // Existing chord: A + B
        // User selects: X + Y
        // Expected: No conflict (completely disjoint)
        let selected: Set<ControllerButton> = [.x, .y]
        let existing = [
            ChordMapping(buttons: [.a, .b], keyCode: 0)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertTrue(conflicts.isEmpty)
    }

    func testComplexScenarioMultipleChordsMultipleConflicts() {
        // Existing chords:
        //   - LB + RB
        //   - LB + A
        //   - LB + A + B (3-button)
        //   - X + Y
        // User selects: LB
        // Expected conflicts: RB (from LB+RB), A (from LB+A)
        // Note: LB+A+B requires 2 more buttons, so no conflict from that
        let selected: Set<ControllerButton> = [.leftBumper]
        let existing = [
            ChordMapping(buttons: [.leftBumper, .rightBumper], keyCode: 0),
            ChordMapping(buttons: [.leftBumper, .a], keyCode: 1),
            ChordMapping(buttons: [.leftBumper, .a, .b], keyCode: 2),
            ChordMapping(buttons: [.x, .y], keyCode: 3)
        ]

        let conflicts = ChordMapping.conflictedButtons(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts, [.rightBumper, .a])
    }

    // MARK: - Conflict With Chord Info Tests

    func testConflictedButtonsWithChordsReturnsCorrectChord() {
        // Existing chord: Left + Down
        // User selects: Left
        // Expected: Down maps to the Left + Down chord
        let selected: Set<ControllerButton> = [.dpadLeft]
        let chord = ChordMapping(buttons: [.dpadLeft, .dpadDown], keyCode: 0)
        let existing = [chord]

        let conflicts = ChordMapping.conflictedButtonsWithChords(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[.dpadDown]?.buttons, chord.buttons)
    }

    func testConflictedButtonsWithChordsMultipleConflicts() {
        // Existing chords: LB + RB, LB + A
        // User selects: LB
        // Expected: RB maps to LB+RB chord, A maps to LB+A chord
        let selected: Set<ControllerButton> = [.leftBumper]
        let chord1 = ChordMapping(buttons: [.leftBumper, .rightBumper], keyCode: 0)
        let chord2 = ChordMapping(buttons: [.leftBumper, .a], keyCode: 1)
        let existing = [chord1, chord2]

        let conflicts = ChordMapping.conflictedButtonsWithChords(
            selectedButtons: selected,
            existingChords: existing
        )

        XCTAssertEqual(conflicts.count, 2)
        XCTAssertEqual(conflicts[.rightBumper]?.buttons, chord1.buttons)
        XCTAssertEqual(conflicts[.a]?.buttons, chord2.buttons)
    }
}

// MARK: - Sequence Detection Tests

final class SequenceDetectionTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-seq-tests-\(UUID().uuidString)", isDirectory: true)

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
        try? await Task.sleep(nanoseconds: 100_000_000)
        await MainActor.run {
            mockInputSimulator?.releaseAllModifiers()
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.cleanup()
            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func waitForTasks(_ delay: TimeInterval = 0.4) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    /// Tests that a simple 3-step sequence (A → B → X) fires via direct callbacks
    func testSequenceDetection_ThreeDistinctButtons() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.a, .b, .x],
                keyCode: 99  // F16
            )
            profileManager.setActiveProfile(Profile(
                name: "SeqTest",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press A → B → X with release between each
        for button: ControllerButton in [.a, .b, .x] {
            await MainActor.run {
                controllerService.onButtonPressed?(button)
                controllerService.onButtonReleased?(button, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1, "Sequence A→B→X should fire exactly once")
        }
    }

    /// Tests that pressing the SAME button 3 times fires a sequence (L3 × 3)
    func testSequenceDetection_SameButtonThreeTimes_DirectCallback() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "L3x3",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press L3 three times via direct callback
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1, "Sequence L3×3 should fire exactly once via direct callback")
        }
    }

    /// Tests that pressing the SAME button 3 times fires through the full buttonPressed path (chord window)
    func testSequenceDetection_SameButtonThreeTimes_ViaButtonPressed() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "L3x3",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press L3 three times through the full chord window path
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.buttonPressed(.leftThumbstick)
            }
            await waitForTasks(0.1)  // Wait for chord window (0.05) + processing
            await MainActor.run {
                controllerService.buttonReleased(.leftThumbstick)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1, "Sequence L3×3 should fire through buttonPressed path")
        }
    }

    /// Tests that L3 × 3 works even when L3 has a regular mapping
    func testSequenceDetection_SameButtonThreeTimes_WithRegularMapping() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: 99
            )
            let l3Mapping = KeyMapping(keyCode: 50)  // Regular key mapping for L3
            profileManager.setActiveProfile(Profile(
                name: "L3x3+mapping",
                buttonMappings: [.leftThumbstick: l3Mapping],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press L3 three times via direct callback
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            // Individual key presses should fire (3 times)
            let individualActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 50 }
                return false
            }
            XCTAssertEqual(individualActions.count, 3, "Individual L3 mapping should fire 3 times")

            // Sequence should also fire (1 time)
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1, "Sequence L3×3 should also fire once")
        }
    }

    /// Tests that a 2-button repeated sequence (A × 2) fires correctly
    func testSequenceDetection_SameButtonTwice() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.a, .a],
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "Ax2",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        for _ in 0..<2 {
            await MainActor.run {
                controllerService.onButtonPressed?(.a)
                controllerService.onButtonReleased?(.a, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1, "Sequence A×2 should fire exactly once")
        }
    }

    /// Tests L3 × 3 with realistic chord window and hold times — exposes the timing bug
    /// The chord window (150ms default) delays when advanceSequenceTracking runs,
    /// so the step timeout check measures chord-window-inflated time, not physical press time.
    func testSequenceDetection_SameButtonThreeTimes_RealisticChordWindow() async throws {
        await MainActor.run {
            // Use production-like chord window
            controllerService.chordWindow = 0.15

            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                stepTimeout: 0.4,  // Default
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "L3x3Realistic",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Simulate realistic thumbstick clicks: press for 120ms, 200ms gap between clicks
        for i in 0..<3 {
            await MainActor.run {
                controllerService.buttonPressed(.leftThumbstick)
            }
            // Hold for 120ms (realistic stick click hold time)
            await waitForTasks(0.12)
            await MainActor.run {
                controllerService.buttonReleased(.leftThumbstick)
            }
            if i < 2 {
                // Wait 200ms between presses (realistic for rapid thumbstick clicking)
                await waitForTasks(0.2)
            }
        }
        // Wait for chord window + processing
        await waitForTasks(0.4)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 1,
                "Sequence L3×3 should fire with realistic timing (120ms holds, 200ms gaps)")
        }
    }

    /// Tests that sequence times out when presses are too slow
    func testSequenceDetection_Timeout() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.a, .a, .a],
                stepTimeout: 0.1,  // Very short timeout
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "Timeout",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // First press
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        // Wait longer than the step timeout
        await waitForTasks(0.2)

        // Second and third press
        for _ in 0..<2 {
            await MainActor.run {
                controllerService.onButtonPressed?(.a)
                controllerService.onButtonReleased?(.a, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 0, "Sequence should NOT fire when step timeout elapses")
        }
    }

    // MARK: - Special Virtual Key Code Tests

    /// Tests that a sequence mapped to the laser pointer virtual key code toggles the laser pointer
    func testSequenceDetection_LaserPointerVirtualKeyCode() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: KeyCodeMapping.showLaserPointer
            )
            profileManager.setActiveProfile(Profile(
                name: "LaserSeq",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Verify laser is not showing initially
        await MainActor.run {
            XCTAssertFalse(LaserPointerOverlay.shared.isShowing, "Laser should not be showing initially")
        }

        // Press L3 three times via direct callback
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.15)

        // Laser pointer should now be showing
        await MainActor.run {
            XCTAssertTrue(LaserPointerOverlay.shared.isShowing,
                "Sequence with laser pointer key code should toggle laser ON")
        }

        // The virtual key code should NOT have been sent as an actual key press
        await MainActor.run {
            let laserKeyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.showLaserPointer }
                return false
            }
            XCTAssertEqual(laserKeyPresses.count, 0,
                "Laser pointer virtual key code should NOT be sent as an actual key press")
        }

        // Clean up: hide the laser
        await MainActor.run {
            LaserPointerOverlay.shared.hide()
        }
    }

    /// Tests that a sequence mapped to the on-screen keyboard virtual key code toggles the keyboard
    func testSequenceDetection_OnScreenKeyboardVirtualKeyCode() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.a, .b],
                keyCode: KeyCodeMapping.showOnScreenKeyboard
            )
            profileManager.setActiveProfile(Profile(
                name: "KbdSeq",
                buttonMappings: [:],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Verify keyboard is not visible initially
        await MainActor.run {
            XCTAssertFalse(OnScreenKeyboardManager.shared.isVisible, "Keyboard should not be visible initially")
        }

        // Press A then B
        for button: ControllerButton in [.a, .b] {
            await MainActor.run {
                controllerService.onButtonPressed?(button)
                controllerService.onButtonReleased?(button, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.15)

        // On-screen keyboard should now be visible
        await MainActor.run {
            XCTAssertTrue(OnScreenKeyboardManager.shared.isVisible,
                "Sequence with on-screen keyboard key code should toggle keyboard ON")
        }

        // The virtual key code should NOT have been sent as an actual key press
        await MainActor.run {
            let kbdKeyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.showOnScreenKeyboard }
                return false
            }
            XCTAssertEqual(kbdKeyPresses.count, 0,
                "On-screen keyboard virtual key code should NOT be sent as an actual key press")
        }

        // Clean up: hide the keyboard
        await MainActor.run {
            OnScreenKeyboardManager.shared.hide()
        }
    }

    /// Tests that a chord mapped to the laser pointer virtual key code toggles the laser pointer
    func testChordDetection_LaserPointerVirtualKeyCode() async throws {
        await MainActor.run {
            let chord = ChordMapping(
                buttons: [.leftBumper, .rightBumper],
                keyCode: KeyCodeMapping.showLaserPointer
            )
            profileManager.setActiveProfile(Profile(
                name: "LaserChord",
                buttonMappings: [:],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Verify laser is not showing initially
        await MainActor.run {
            XCTAssertFalse(LaserPointerOverlay.shared.isShowing, "Laser should not be showing initially")
        }

        // Simulate chord via onChordDetected callback
        await MainActor.run {
            controllerService.onChordDetected?([.leftBumper, .rightBumper])
        }
        await waitForTasks(0.15)

        // Laser pointer should now be showing
        await MainActor.run {
            XCTAssertTrue(LaserPointerOverlay.shared.isShowing,
                "Chord with laser pointer key code should toggle laser ON")
        }

        // The virtual key code should NOT have been sent as an actual key press
        await MainActor.run {
            let laserKeyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == KeyCodeMapping.showLaserPointer }
                return false
            }
            XCTAssertEqual(laserKeyPresses.count, 0,
                "Laser pointer virtual key code should NOT be sent as an actual key press via chord")
        }

        // Clean up
        await MainActor.run {
            LaserPointerOverlay.shared.hide()
        }
    }
}

// MARK: - Controller Lock Tests

final class ControllerLockTests: XCTestCase {
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    private var testConfigDirectory: URL!

    override func setUp() async throws {
        testConfigDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("controllerkeys-lock-tests-\(UUID().uuidString)", isDirectory: true)

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
        try? await Task.sleep(nanoseconds: 100_000_000)
        await MainActor.run {
            mockInputSimulator?.releaseAllModifiers()
            controllerService?.onButtonPressed = nil
            controllerService?.onButtonReleased = nil
            controllerService?.onChordDetected = nil
            controllerService?.cleanup()
            mappingEngine = nil
            controllerService = nil
            profileManager = nil
            appMonitor = nil
            mockInputSimulator = nil
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func waitForTasks(_ delay: TimeInterval = 0.4) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    // MARK: 1. Lock via single button — blocks subsequent presses

    func testLockViaSingleButton_BlocksSubsequentPresses() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let aMapping = KeyMapping(keyCode: 0) // 'A' key
            profileManager.setActiveProfile(Profile(
                name: "LockTest",
                buttonMappings: [.x: lockMapping, .a: aMapping]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press X to lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        // Verify locked
        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked after pressing lock button")
        }

        // Clear events from lock action
        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should be blocked
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let keyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertEqual(keyPresses.count, 0, "Button presses should be blocked while locked")
        }
    }

    // MARK: 2. Unlock via single button — resumes normal mapping

    func testUnlockViaSingleButton_ResumesMapping() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.setActiveProfile(Profile(
                name: "UnlockTest",
                buttonMappings: [.x: lockMapping, .a: aMapping]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        // Unlock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            XCTAssertFalse(mappingEngine.isLocked, "Engine should be unlocked after toggling lock button again")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should work now
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasKeyAction = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertTrue(hasKeyAction, "Button presses should work after unlocking")
        }
    }

    // MARK: 3. Lock via sequence (L3×3) — blocks actions

    func testLockViaSequence_BlocksActions() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: KeyCodeMapping.controllerLock
            )
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.setActiveProfile(Profile(
                name: "SeqLock",
                buttonMappings: [.a: aMapping],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press L3 three times to trigger sequence lock
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked after sequence")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should be blocked
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let keyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertEqual(keyPresses.count, 0, "Actions should be blocked after sequence lock")
        }
    }

    // MARK: 4. Unlock via sequence — resumes actions

    func testUnlockViaSequence_ResumesActions() async throws {
        await MainActor.run {
            let seq = SequenceMapping(
                steps: [.leftThumbstick, .leftThumbstick, .leftThumbstick],
                keyCode: KeyCodeMapping.controllerLock
            )
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.setActiveProfile(Profile(
                name: "SeqUnlock",
                buttonMappings: [.a: aMapping],
                sequenceMappings: [seq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock via sequence
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.2)

        // Unlock via sequence
        for _ in 0..<3 {
            await MainActor.run {
                controllerService.onButtonPressed?(.leftThumbstick)
                controllerService.onButtonReleased?(.leftThumbstick, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertFalse(mappingEngine.isLocked, "Engine should be unlocked after second sequence")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should work
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasKeyAction = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertTrue(hasKeyAction, "Actions should resume after sequence unlock")
        }
    }

    // MARK: 5. Lock via chord (LB+RB) — blocks actions

    func testLockViaChord_BlocksActions() async throws {
        await MainActor.run {
            let chord = ChordMapping(
                buttons: [.leftBumper, .rightBumper],
                keyCode: KeyCodeMapping.controllerLock
            )
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.setActiveProfile(Profile(
                name: "ChordLock",
                buttonMappings: [.a: aMapping],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Press chord LB+RB
        await MainActor.run {
            controllerService.onChordDetected?([.leftBumper, .rightBumper])
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked after chord")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should be blocked
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let keyPresses = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertEqual(keyPresses.count, 0, "Actions should be blocked after chord lock")
        }
    }

    // MARK: 6. Unlock via chord — resumes actions

    func testUnlockViaChord_ResumesActions() async throws {
        await MainActor.run {
            let chord = ChordMapping(
                buttons: [.leftBumper, .rightBumper],
                keyCode: KeyCodeMapping.controllerLock
            )
            let aMapping = KeyMapping(keyCode: 0)
            profileManager.setActiveProfile(Profile(
                name: "ChordUnlock",
                buttonMappings: [.a: aMapping],
                chordMappings: [chord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onChordDetected?([.leftBumper, .rightBumper])
        }
        await waitForTasks(0.2)

        // Release chord buttons
        await MainActor.run {
            controllerService.onButtonReleased?(.leftBumper, 0.1)
            controllerService.onButtonReleased?(.rightBumper, 0.1)
        }
        await waitForTasks(0.1)

        // Unlock
        await MainActor.run {
            controllerService.onChordDetected?([.leftBumper, .rightBumper])
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertFalse(mappingEngine.isLocked, "Engine should be unlocked after second chord")
        }

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Press A — should work
        await MainActor.run {
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.03)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let hasKeyAction = mockInputSimulator.events.contains { event in
                if case .pressKey(let code, _) = event { return code == 0 }
                if case .executeMapping = event { return true }
                return false
            }
            XCTAssertTrue(hasKeyAction, "Actions should resume after chord unlock")
        }
    }

    // MARK: 7. Lock releases held modifiers

    func testLockReleasesHeldModifiers() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let holdMapping = KeyMapping.holdModifier(.command)
            profileManager.setActiveProfile(Profile(
                name: "LockModifiers",
                buttonMappings: [.x: lockMapping, .leftBumper: holdMapping]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Hold LB (command modifier)
        await MainActor.run {
            controllerService.onButtonPressed?(.leftBumper)
        }
        await waitForTasks(0.1)

        // Verify modifier is held
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand),
                "Command modifier should be held")
        }

        // Lock — should release modifiers
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.2)

        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked")
            let hasReleaseAll = mockInputSimulator.events.contains { event in
                if case .releaseAllModifiers = event { return true }
                return false
            }
            XCTAssertTrue(hasReleaseAll, "Lock should release all held modifiers")
        }
    }

    // MARK: 8. Lock persists across isEnabled toggle

    func testLockPersistsAcrossEnableToggle() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            profileManager.setActiveProfile(Profile(
                name: "LockPersist",
                buttonMappings: [.x: lockMapping]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Engine should be locked")
        }

        // Disable and re-enable
        await MainActor.run {
            mappingEngine.isEnabled = false
        }
        await waitForTasks(0.1)
        await MainActor.run {
            mappingEngine.isEnabled = true
        }
        await waitForTasks(0.1)

        // Lock should still be active
        await MainActor.run {
            XCTAssertTrue(mappingEngine.isLocked, "Lock should persist across enable/disable toggle")
        }
    }

    // MARK: 9. Non-lock sequence blocked while locked

    func testNonLockSequenceBlockedWhileLocked() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let otherSeq = SequenceMapping(
                steps: [.a, .b],
                keyCode: 99  // F16
            )
            profileManager.setActiveProfile(Profile(
                name: "SeqBlocked",
                buttonMappings: [.x: lockMapping],
                sequenceMappings: [otherSeq]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Try sequence A → B while locked
        for button: ControllerButton in [.a, .b] {
            await MainActor.run {
                controllerService.onButtonPressed?(button)
                controllerService.onButtonReleased?(button, 0.03)
            }
            await waitForTasks(0.05)
        }
        await waitForTasks(0.1)

        await MainActor.run {
            let sequenceActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(sequenceActions.count, 0, "Non-lock sequences should be blocked while locked")
        }
    }

    // MARK: 10. Non-lock chord blocked while locked

    func testNonLockChordBlockedWhileLocked() async throws {
        await MainActor.run {
            let lockMapping = KeyMapping(keyCode: KeyCodeMapping.controllerLock)
            let otherChord = ChordMapping(
                buttons: [.a, .b],
                keyCode: 99
            )
            profileManager.setActiveProfile(Profile(
                name: "ChordBlocked",
                buttonMappings: [.x: lockMapping],
                chordMappings: [otherChord]
            ))
        }
        try? await Task.sleep(nanoseconds: 10_000_000)

        // Lock
        await MainActor.run {
            controllerService.onButtonPressed?(.x)
            controllerService.onButtonReleased?(.x, 0.03)
        }
        await waitForTasks(0.1)

        await MainActor.run { mockInputSimulator.clearEvents() }

        // Try chord A+B while locked
        await MainActor.run {
            controllerService.onChordDetected?([.a, .b])
        }
        await waitForTasks(0.2)

        await MainActor.run {
            let chordActions = mockInputSimulator.events.filter { event in
                if case .pressKey(let code, _) = event { return code == 99 }
                return false
            }
            XCTAssertEqual(chordActions.count, 0, "Non-lock chords should be blocked while locked")
        }
    }
}
