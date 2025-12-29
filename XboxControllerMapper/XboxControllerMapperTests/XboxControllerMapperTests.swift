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

    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags) {
        events.append(.pressKey(keyCode, modifiers))
    }
    
    func holdModifier(_ modifier: CGEventFlags) {
        heldModifiers.insert(modifier)
        events.append(.holdModifier(modifier))
    }
    
    func releaseModifier(_ modifier: CGEventFlags) {
        heldModifiers.remove(modifier)
        events.append(.releaseModifier(modifier))
    }
    
    func releaseAllModifiers() {
        heldModifiers = []
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
            heldModifiers.insert(mapping.modifiers.cgEventFlags)
        }
        events.append(.startHoldMapping(mapping))
    }
    
    func stopHoldMapping(_ mapping: KeyMapping) {
        if mapping.modifiers.hasAny {
            heldModifiers.remove(mapping.modifiers.cgEventFlags)
        }
        events.append(.stopHoldMapping(mapping))
    }
}

// MARK: - Tests

@MainActor
final class XboxControllerMapperTests: XCTestCase {
    
    var controllerService: ControllerService!
    var profileManager: ProfileManager!
    var appMonitor: AppMonitor!
    var mockInputSimulator: MockInputSimulator!
    var mappingEngine: MappingEngine!
    
    override func setUp() async throws {
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
    
    func testModifierCombinationMapping() throws {
        // Setup: LB -> Hold Command + Shift, A -> Key 'S'
        
        let lbMapping = KeyMapping(
            modifiers: ModifierFlags(command: true, shift: true),
            isHoldModifier: true
        )
        
        let aMapping = KeyMapping(keyCode: 1) // Key 'S'
        
        let profile = Profile(
            name: "Test Profile",
            buttonMappings: [
                .leftBumper: lbMapping,
                .a: aMapping
            ]
        )
        
        profileManager.setActiveProfile(profile)
        
        guard let onButtonPressed = controllerService.onButtonPressed else {
            XCTFail("MappingEngine didn't set onButtonPressed")
            return
        }
        
        guard let onButtonReleased = controllerService.onButtonReleased else {
            XCTFail("MappingEngine didn't set onButtonReleased")
            return
        }
        
        // 1. Press Left Bumper
        onButtonPressed(.leftBumper)
        
        let expectation1 = XCTestExpectation(description: "LB Pressed processed")
        DispatchQueue.main.async { expectation1.fulfill() }
        wait(for: [expectation1], timeout: 1.0)
        
        XCTAssertTrue(mockInputSimulator.events.contains { event in
            if case .startHoldMapping(let mapping) = event {
                return mapping.isHoldModifier && mapping.modifiers.command && mapping.modifiers.shift
            }
            return false
        }, "Should have started holding modifiers")
        
        // 2. Press A
        onButtonPressed(.a)
        
        let expectation2 = XCTestExpectation(description: "A Pressed processed")
        DispatchQueue.main.async { expectation2.fulfill() }
        wait(for: [expectation2], timeout: 1.0)
        
        // 3. Release A (trigger)
        onButtonReleased(.a, 0.1)
        
        let expectation3 = XCTestExpectation(description: "A Released processed")
        DispatchQueue.main.async { expectation3.fulfill() }
        wait(for: [expectation3], timeout: 1.0)
        
        // Verify 'S' was pressed
        // And importantly, that modifiers were held at that time
        
        XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskCommand), "Command should be held during A press")
        XCTAssertTrue(mockInputSimulator.heldModifiers.contains(.maskShift), "Shift should be held during A press")
        
        XCTAssertTrue(mockInputSimulator.events.contains { event in
            if case .executeMapping(let mapping) = event {
                return mapping.keyCode == 1
            }
            return false
        }, "Should have executed mapping for 'S'")
    }
    
    func testSimultaneousPressWithNoChordMapping() throws {
        // Setup: LB -> Hold Command + Shift, A -> Key 'S'
        // No chord mapping defined for LB + A
        
        let lbMapping = KeyMapping(
            modifiers: ModifierFlags(command: true, shift: true),
            isHoldModifier: true
        )
        
        let aMapping = KeyMapping(keyCode: 1) // Key 'S'
        
        let profile = Profile(
            name: "Test Profile",
            buttonMappings: [
                .leftBumper: lbMapping,
                .a: aMapping
            ]
        )
        
        profileManager.setActiveProfile(profile)
        
        guard let onChordDetected = controllerService.onChordDetected else {
            XCTFail("MappingEngine didn't set onChordDetected")
            return
        }
        
        // Simulate simultaneous press (Chord detected by ControllerService)
        // This happens when buttons are pressed within 50ms of each other
        onChordDetected([.leftBumper, .a])
        
        let expectation = XCTestExpectation(description: "Chord processed")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)
        
        // Expectation: Since no chord mapping exists, it should fall back to individual actions.
        // LB should start holding immediately (as it's a hold modifier)
        
        XCTAssertTrue(mockInputSimulator.events.contains { event in
            if case .startHoldMapping(let mapping) = event {
                return mapping.isHoldModifier && mapping.modifiers.command && mapping.modifiers.shift
            }
            return false
        }, "Should have started holding modifiers (fallback behavior)")
        
        // A is a key mapping, which triggers on release (to distinguish from long hold)
        // So we must simulate release of A
        guard let onButtonReleased = controllerService.onButtonReleased else {
             XCTFail("MappingEngine didn't set onButtonReleased")
             return
        }
        
        onButtonReleased(.a, 0.1)
        
        let expectation2 = XCTestExpectation(description: "A Release processed")
        DispatchQueue.main.async { expectation2.fulfill() }
        wait(for: [expectation2], timeout: 1.0)
        
        // Now 'S' should be executed
        XCTAssertTrue(mockInputSimulator.events.contains { event in
            if case .executeMapping(let mapping) = event {
                return mapping.keyCode == 1
            }
            return false
        }, "Should have executed mapping for 'S' (fallback behavior)")
    }
}