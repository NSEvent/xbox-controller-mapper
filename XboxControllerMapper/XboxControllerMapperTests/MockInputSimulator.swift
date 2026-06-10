import Foundation
import CoreGraphics
@testable import ControllerKeys

@MainActor
extension ProfileManager {
    func installTestProfile(_ profile: Profile) {
        profiles = [profile]
        setActiveProfile(profile)
    }
}

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

    func scroll(event scrollEvent: ScrollEvent) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(.scroll(scrollEvent.dx, scrollEvent.dy))
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
