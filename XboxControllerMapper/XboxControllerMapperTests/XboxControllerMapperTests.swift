import XCTest
import Combine
import CoreGraphics
@testable import XboxControllerMapper

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
    
    var events: [Event] = []
    var heldModifiers: CGEventFlags = []
    private var modifierCounts: [UInt64: Int] = [:]

    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {
        events.append(.pressKey(keyCode, modifiers))
    }
    
    func holdModifier(_ modifier: CGEventFlags) {
        let masks: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        for mask in masks where modifier.contains(mask) {
            let count = modifierCounts[mask.rawValue] ?? 0
            modifierCounts[mask.rawValue] = count + 1
            if count == 0 {
                heldModifiers.insert(mask)
            }
        }
        events.append(.holdModifier(modifier))
    }
    
    func releaseModifier(_ modifier: CGEventFlags) {
        let masks: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        for mask in masks where modifier.contains(mask) {
            let count = modifierCounts[mask.rawValue] ?? 0
            if count > 0 {
                modifierCounts[mask.rawValue] = count - 1
                if count == 1 {
                    heldModifiers.remove(mask)
                }
            }
        }
        events.append(.releaseModifier(modifier))
    }
    
    func releaseAllModifiers() {
        heldModifiers = []
        modifierCounts.removeAll()
        events.append(.releaseAllModifiers)
    }
    
    func moveMouse(dx: CGFloat, dy: CGFloat) {
        events.append(.moveMouse(dx, dy))
    }
    
    func scroll(dx: CGFloat, dy: CGFloat) {
        events.append(.scroll(dx, dy))
    }
    
    func executeMapping(_ mapping: KeyMapping) {
        events.append(.executeMapping(mapping))
    }
    
    func startHoldMapping(_ mapping: KeyMapping) {
        if mapping.modifiers.hasAny {
            holdModifier(mapping.modifiers.cgEventFlags)
        }
        events.append(.startHoldMapping(mapping))
    }
    
    func stopHoldMapping(_ mapping: KeyMapping) {
        if mapping.modifiers.hasAny {
            releaseModifier(mapping.modifiers.cgEventFlags)
        }
        events.append(.stopHoldMapping(mapping))
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
    
    private func waitForTasks(_ delay: TimeInterval = 0.3) async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await Task.yield()
    }

    func testModifierCombinationMapping() async throws {
        await MainActor.run {
            let lbMapping = KeyMapping.holdModifier(.command)
            let aMapping = KeyMapping(keyCode: 1)
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [.leftBumper: lbMapping, .a: aMapping]))
            
            controllerService.buttonPressed(.leftBumper)
        }
        await waitForTasks()
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand))
            controllerService.buttonPressed(.a)
            controllerService.buttonReleased(.a)
        }
        await waitForTasks()
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            })
        }
    }
    
    func testSimultaneousPressWithNoChordMapping() async throws {
        await MainActor.run {
            let lbMapping = KeyMapping.holdModifier(.command)
            let aMapping = KeyMapping(keyCode: 1)
            profileManager.setActiveProfile(Profile(name: "Test", buttonMappings: [.leftBumper: lbMapping, .a: aMapping]))
            
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
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 1 }
                return false
            })
        }
    }
    
    func testDoubleTapWithHeldModifier() async throws {
        await MainActor.run {
            let lbMapping = KeyMapping.holdModifier(.command)
            let doubleTap = DoubleTapMapping(keyCode: 2, threshold: 0.2)
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.doubleTapMapping = doubleTap
            profileManager.setActiveProfile(Profile(name: "DT", buttonMappings: [.leftBumper: lbMapping, .a: aMapping]))
            
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
    
    func testAppSpecificOverride() async throws {
        await MainActor.run {
            var profile = Profile(name: "App", buttonMappings: [.a: .key(1)])
            profile.appOverrides["com.test.app"] = [.a: .key(2)]
            profileManager.setActiveProfile(profile)
            appMonitor.frontmostBundleId = "com.test.app"
            controllerService.onButtonPressed?(.a)
            controllerService.onButtonReleased?(.a, 0.1)
        }
        await waitForTasks()
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event { return mapping.keyCode == 2 }
                return false
            })
        }
    }
    
    func testLongHold() async throws {
        await MainActor.run {
            var aMapping = KeyMapping(keyCode: 1)
            aMapping.longHoldMapping = LongHoldMapping(keyCode: 2, threshold: 0.1)
            profileManager.setActiveProfile(Profile(name: "Hold", buttonMappings: [.a: aMapping]))
            controllerService.buttonPressed(.a)
        }
        await waitForTasks(0.2)
        
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
        
        await MainActor.run {
            controllerService.leftStick = CGPoint(x: 0.5, y: 0.5)
        }
        await waitForTasks(0.2)
        
        await MainActor.run {
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .moveMouse = event { return true }
                return false
            })
        }
    }
    
    func testEngineDisablingReleasesModifiers() async throws {
        await MainActor.run {
            profileManager.setActiveProfile(Profile(name: "T", buttonMappings: [.leftBumper: .holdModifier(.command)]))
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
            // Verify: Up Arrow was executed
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.upArrow
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
            // Verify: executeMapping was called with Cmd + Delete
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.delete && mapping.modifiers.command
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
            // Verify: Delete was executed
            XCTAssertTrue(mockInputSimulator.events.contains { event in
                if case .executeMapping(let mapping) = event {
                    return mapping.keyCode == KeyCodeMapping.delete
                }
                return false
            }, "Delete should have been executed")
            
            // Verify: Cmd was held during execution
            // (Mock records state at startHoldMapping and executeMapping)
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
}
