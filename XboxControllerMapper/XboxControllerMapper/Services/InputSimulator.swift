import Foundation
import CoreGraphics
import AppKit

protocol InputSimulatorProtocol {
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags)
    func holdModifier(_ modifier: CGEventFlags)
    func releaseModifier(_ modifier: CGEventFlags)
    func releaseAllModifiers()
    func moveMouse(dx: CGFloat, dy: CGFloat)
    func scroll(dx: CGFloat, dy: CGFloat)
    func executeMapping(_ mapping: KeyMapping)
    func startHoldMapping(_ mapping: KeyMapping)
    func stopHoldMapping(_ mapping: KeyMapping)
}

/// Service for simulating keyboard and mouse input via CGEvent
class InputSimulator: InputSimulatorProtocol {
    private let eventSource: CGEventSource?

    /// Currently held modifier flags (for hold-type mappings)
    private var heldModifiers: CGEventFlags = []
    
    /// Reference counts for each modifier key to support overlapping mappings
    private var modifierCounts: [UInt64: Int] = [
        CGEventFlags.maskCommand.rawValue: 0,
        CGEventFlags.maskAlternate.rawValue: 0,
        CGEventFlags.maskShift.rawValue: 0,
        CGEventFlags.maskControl.rawValue: 0
    ]

    /// Track if we've warned about accessibility
    private var hasWarnedAboutAccessibility = false

    init() {
        // .hidSystemState simulates hardware-level events, which are often more reliable for system shortcuts
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

        // We only need to simulate modifiers that aren't already held
        let modifiersToPress = modifiers.subtracting(heldModifiers)
        
        // Start with currently held flags
        var currentFlags = heldModifiers

        #if DEBUG
        print("🎮 Pressing key: \(keyCode) with modifiers: \(modifiers.rawValue) (Simulating: \(modifiersToPress.rawValue))")
        print("   Current held modifiers: \(heldModifiers.rawValue)")
        #endif

        // Helper to press modifier
        func pressMod(_ key: Int, flag: CGEventFlags) {
            currentFlags.insert(flag)
            postKeyEvent(keyCode: CGKeyCode(key), keyDown: true, flags: currentFlags)
            usleep(20000) // 20ms delay between modifiers
        }

        // Press modifier keys first (Command -> Shift -> Option -> Control)
        if modifiersToPress.contains(.maskCommand) { pressMod(kVK_Command, flag: .maskCommand) }
        if modifiersToPress.contains(.maskShift)   { pressMod(kVK_Shift,   flag: .maskShift) }
        if modifiersToPress.contains(.maskAlternate){ pressMod(kVK_Option,  flag: .maskAlternate) }
        if modifiersToPress.contains(.maskControl) { pressMod(kVK_Control, flag: .maskControl) }

        // Small delay after modifiers
        if !modifiersToPress.isEmpty {
            usleep(20000) // 20ms
        }

        // Press the main key with all flags active
        postKeyEvent(keyCode: keyCode, keyDown: true, flags: currentFlags)
        usleep(50000) // 50ms press duration
        postKeyEvent(keyCode: keyCode, keyDown: false, flags: currentFlags)

        // Small delay before releasing modifiers
        if !modifiersToPress.isEmpty {
            usleep(20000) // 20ms
        }

        // Helper to release modifier
        func releaseMod(_ key: Int, flag: CGEventFlags) {
            currentFlags.remove(flag)
            postKeyEvent(keyCode: CGKeyCode(key), keyDown: false, flags: currentFlags)
            usleep(20000) // 20ms delay between releases
        }

        // Release modifier keys (Control -> Option -> Shift -> Command)
        if modifiersToPress.contains(.maskControl) { releaseMod(kVK_Control, flag: .maskControl) }
        if modifiersToPress.contains(.maskAlternate){ releaseMod(kVK_Option,  flag: .maskAlternate) }
        if modifiersToPress.contains(.maskShift)   { releaseMod(kVK_Shift,   flag: .maskShift) }
        if modifiersToPress.contains(.maskCommand) { releaseMod(kVK_Command, flag: .maskCommand) }

        #if DEBUG
        print("  ✅ Key sequence completed")
        #endif
    }

    /// Posts a single key event
    private func postKeyEvent(keyCode: CGKeyCode, keyDown: Bool, flags: CGEventFlags = []) {
        // Use the configured source
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: keyDown) else {
            #if DEBUG
            print("  ❌ Failed to create event for keyCode \(keyCode)")
            #endif
            return
        }

        if flags.rawValue != 0 {
            event.flags = flags
        }

        // Post to HID tap
        event.post(tap: .cghidEventTap)
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
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let masks: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        let vKeys: [UInt64: Int] = [
            CGEventFlags.maskCommand.rawValue: kVK_Command,
            CGEventFlags.maskAlternate.rawValue: kVK_Option,
            CGEventFlags.maskShift.rawValue: kVK_Shift,
            CGEventFlags.maskControl.rawValue: kVK_Control
        ]

        for mask in masks where modifier.contains(mask) {
            let key = mask.rawValue
            let count = modifierCounts[key] ?? 0
            modifierCounts[key] = count + 1
            
            if count == 0 {
                // First time this modifier is being held
                heldModifiers.insert(mask)
                if let vKey = vKeys[key] {
                    CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKey), keyDown: true)?
                        .post(tap: .cghidEventTap)
                }
            }
        }
    }

    /// Stops holding a modifier
    func releaseModifier(_ modifier: CGEventFlags) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let masks: [CGEventFlags] = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        let vKeys: [UInt64: Int] = [
            CGEventFlags.maskCommand.rawValue: kVK_Command,
            CGEventFlags.maskAlternate.rawValue: kVK_Option,
            CGEventFlags.maskShift.rawValue: kVK_Shift,
            CGEventFlags.maskControl.rawValue: kVK_Control
        ]

        for mask in masks where modifier.contains(mask) {
            let key = mask.rawValue
            let count = modifierCounts[key] ?? 0
            if count > 0 {
                modifierCounts[key] = count - 1
                
                if count == 1 {
                    // Last button holding this modifier released
                    heldModifiers.remove(mask)
                    if let vKey = vKeys[key] {
                        CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKey), keyDown: false)?
                            .post(tap: .cghidEventTap)
                    }
                }
            }
        }
    }

    /// Releases all held modifiers
    func releaseAllModifiers() {
        let currentHeld = heldModifiers
        releaseModifier(currentHeld)
        // Reset all counts to zero
        for key in modifierCounts.keys {
            modifierCounts[key] = 0
        }
        heldModifiers = []
    }

    // MARK: - Mouse Button State

    /// Tracks currently held mouse buttons to determine if moving should be a drag
    private var heldMouseButtons: Set<CGMouseButton> = []

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

        // Determine event type based on held buttons (drag if button held)
        let eventType: CGEventType
        let mouseButton: CGMouseButton

        if heldMouseButtons.contains(.left) {
            eventType = .leftMouseDragged
            mouseButton = .left
        } else if heldMouseButtons.contains(.right) {
            eventType = .rightMouseDragged
            mouseButton = .right
        } else if heldMouseButtons.contains(.center) {
            eventType = .otherMouseDragged
            mouseButton = .center
        } else {
            eventType = .mouseMoved
            mouseButton = .left // Default for move events
        }

        if let event = CGEvent(
            mouseEventSource: source,
            mouseType: eventType,
            mouseCursorPosition: CGPoint(x: newX, y: newY),
            mouseButton: mouseButton
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
        // Helper to ensure precise click timing if needed, or just sequence them
        // For simulated clicks, immediate up is usually fine, but physically
        // distinct events are safer.
        mouseButtonUp(keyCode)
    }

    private func mouseButtonDown(_ keyCode: CGKeyCode) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let location = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let cgLocation = CGPoint(x: location.x, y: screenHeight - location.y)

        let (downType, button) = mouseEventType(for: keyCode, down: true)

        // Track hold state
        heldMouseButtons.insert(button)

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

        // Update hold state
        heldMouseButtons.remove(button)

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
        #if DEBUG
        print("📋 executeMapping called:")
        print("   keyCode: \(mapping.keyCode?.description ?? "nil")")
        print("   modifiers - cmd:\(mapping.modifiers.command) opt:\(mapping.modifiers.option) shift:\(mapping.modifiers.shift) ctrl:\(mapping.modifiers.control)")
        print("   cgEventFlags: \(mapping.modifiers.cgEventFlags.rawValue)")
        print("   isHoldModifier: \(mapping.isHoldModifier)")
        #endif

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
        // Hold any modifiers
        if mapping.modifiers.hasAny {
            holdModifier(mapping.modifiers.cgEventFlags)
        }
        // Hold the key/mouse button
        if let keyCode = mapping.keyCode {
            keyDown(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        }
    }

    /// Stops holding a mapping
    func stopHoldMapping(_ mapping: KeyMapping) {
        // Release the key/mouse button first
        if let keyCode = mapping.keyCode {
            keyUp(keyCode)
        }
        // Then release modifiers
        if mapping.modifiers.hasAny {
            releaseModifier(mapping.modifiers.cgEventFlags)
        }
    }
}

// Import Carbon for key codes
import Carbon.HIToolbox

private let kVK_Command = 0x37
private let kVK_Shift = 0x38
private let kVK_Option = 0x3A
private let kVK_Control = 0x3B
