import Foundation
import CoreGraphics
import AppKit

/// Service for simulating keyboard and mouse input via CGEvent
class InputSimulator {
    private let eventSource: CGEventSource?

    /// Currently held modifier flags (for hold-type mappings)
    private var heldModifiers: CGEventFlags = []

    /// Track if we've warned about accessibility
    private var hasWarnedAboutAccessibility = false

    init() {
        eventSource = CGEventSource(stateID: .hidSystemState)
        if eventSource == nil {
            print("⚠️ Failed to create CGEventSource - input simulation may not work")
        }
    }

    /// Check if we can post events (accessibility enabled)
    private func checkAccessibility() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted && !hasWarnedAboutAccessibility {
            hasWarnedAboutAccessibility = true
            print("⚠️ Cannot post events - Accessibility permissions not granted")
        }
        return trusted
    }

    // MARK: - Keyboard Simulation

    /// Simulates a key press with optional modifiers
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        // Handle mouse button "key codes"
        if KeyCodeMapping.isMouseButton(keyCode) {
            pressMouseButton(keyCode)
            return
        }

        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        // Combine explicit modifiers with any held modifiers
        let combinedModifiers = modifiers.union(heldModifiers)

        #if DEBUG
        print("🎮 Pressing key: \(keyCode) with modifiers: \(combinedModifiers.rawValue)")
        #endif

        // Key down
        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            event.flags = combinedModifiers
            event.post(tap: .cghidEventTap)
        }

        // Key up
        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            event.flags = combinedModifiers
            event.post(tap: .cghidEventTap)
        }
    }

    /// Holds a key down (for continuous actions)
    func keyDown(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        if KeyCodeMapping.isMouseButton(keyCode) {
            mouseButtonDown(keyCode)
            return
        }

        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let combinedModifiers = modifiers.union(heldModifiers)

        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            event.flags = combinedModifiers
            event.post(tap: .cghidEventTap)
        }
    }

    /// Releases a held key
    func keyUp(_ keyCode: CGKeyCode) {
        if KeyCodeMapping.isMouseButton(keyCode) {
            mouseButtonUp(keyCode)
            return
        }

        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            event.flags = heldModifiers
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Modifier Management

    /// Starts holding a modifier (for bumper/trigger modifier mappings)
    func holdModifier(_ modifier: CGEventFlags) {
        heldModifiers.insert(modifier)

        // Post modifier key down events
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        if modifier.contains(.maskCommand) {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)?
                .post(tap: .cghidEventTap)
        }
        if modifier.contains(.maskAlternate) {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Option), keyDown: true)?
                .post(tap: .cghidEventTap)
        }
        if modifier.contains(.maskShift) {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: true)?
                .post(tap: .cghidEventTap)
        }
        if modifier.contains(.maskControl) {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: true)?
                .post(tap: .cghidEventTap)
        }
    }

    /// Stops holding a modifier
    func releaseModifier(_ modifier: CGEventFlags) {
        heldModifiers.remove(modifier)

        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        if modifier.contains(.maskCommand) {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)?
                .post(tap: .cghidEventTap)
        }
        if modifier.contains(.maskAlternate) {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Option), keyDown: false)?
                .post(tap: .cghidEventTap)
        }
        if modifier.contains(.maskShift) {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)?
                .post(tap: .cghidEventTap)
        }
        if modifier.contains(.maskControl) {
            CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: false)?
                .post(tap: .cghidEventTap)
        }
    }

    /// Releases all held modifiers
    func releaseAllModifiers() {
        releaseModifier(heldModifiers)
        heldModifiers = []
    }

    // MARK: - Mouse Simulation

    /// Moves the mouse cursor by a delta
    func moveMouse(dx: CGFloat, dy: CGFloat) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let currentLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0

        // Convert from bottom-left origin to top-left origin
        let newX = currentLocation.x + dx
        let newY = screenHeight - currentLocation.y + dy

        if let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: newX, y: newY),
            mouseButton: .left
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    /// Scrolls by a delta
    func scroll(dx: CGFloat, dy: CGFloat) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        if let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Mouse Button Simulation

    private func pressMouseButton(_ keyCode: CGKeyCode) {
        mouseButtonDown(keyCode)
        mouseButtonUp(keyCode)
    }

    private func mouseButtonDown(_ keyCode: CGKeyCode) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let cgLocation = CGPoint(x: location.x, y: screenHeight - location.y)

        let (downType, button) = mouseEventType(for: keyCode, down: true)

        if let event = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: cgLocation,
            mouseButton: button
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func mouseButtonUp(_ keyCode: CGKeyCode) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let cgLocation = CGPoint(x: location.x, y: screenHeight - location.y)

        let (upType, button) = mouseEventType(for: keyCode, down: false)

        if let event = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: cgLocation,
            mouseButton: button
        ) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func mouseEventType(for keyCode: CGKeyCode, down: Bool) -> (CGEventType, CGMouseButton) {
        switch keyCode {
        case KeyCodeMapping.mouseLeftClick:
            return (down ? .leftMouseDown : .leftMouseUp, .left)
        case KeyCodeMapping.mouseRightClick:
            return (down ? .rightMouseDown : .rightMouseUp, .right)
        case KeyCodeMapping.mouseMiddleClick:
            return (down ? .otherMouseDown : .otherMouseUp, .center)
        default:
            return (down ? .leftMouseDown : .leftMouseUp, .left)
        }
    }

    // MARK: - Mapping Execution

    /// Executes a key mapping
    func executeMapping(_ mapping: KeyMapping) {
        if mapping.isHoldModifier {
            // This is handled by hold/release methods
            return
        }

        if let keyCode = mapping.keyCode {
            pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            // Modifier-only mapping - tap the modifiers
            let flags = mapping.modifiers.cgEventFlags
            holdModifier(flags)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.releaseModifier(flags)
            }
        }
    }

    /// Starts holding a mapping (for hold-type mappings)
    func startHoldMapping(_ mapping: KeyMapping) {
        if mapping.isHoldModifier {
            holdModifier(mapping.modifiers.cgEventFlags)
        } else if let keyCode = mapping.keyCode {
            keyDown(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        }
    }

    /// Stops holding a mapping
    func stopHoldMapping(_ mapping: KeyMapping) {
        if mapping.isHoldModifier {
            releaseModifier(mapping.modifiers.cgEventFlags)
        } else if let keyCode = mapping.keyCode {
            keyUp(keyCode)
        }
    }
}

// Import Carbon for key codes
import Carbon.HIToolbox

private let kVK_Command = 0x37
private let kVK_Shift = 0x38
private let kVK_Option = 0x3A
private let kVK_Control = 0x3B
