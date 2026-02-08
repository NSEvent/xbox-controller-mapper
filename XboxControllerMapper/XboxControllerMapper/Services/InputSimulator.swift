import Foundation
import CoreGraphics
import AppKit
import IOKit.hidsystem

protocol InputSimulatorProtocol: Sendable {
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags)
    func holdModifier(_ modifier: CGEventFlags)
    func releaseModifier(_ modifier: CGEventFlags)
    func releaseAllModifiers()
    func isHoldingModifiers(_ modifier: CGEventFlags) -> Bool
    func moveMouse(dx: CGFloat, dy: CGFloat)
    func scroll(
        dx: CGFloat,
        dy: CGFloat,
        phase: CGScrollPhase?,
        momentumPhase: CGMomentumScrollPhase?,
        isContinuous: Bool,
        flags: CGEventFlags
    )
    func executeMapping(_ mapping: KeyMapping)
    func startHoldMapping(_ mapping: KeyMapping)
    func stopHoldMapping(_ mapping: KeyMapping)
    func executeMacro(_ macro: Macro)
}

extension InputSimulatorProtocol {
    func scroll(dx: CGFloat, dy: CGFloat) {
        scroll(dx: dx, dy: dy, phase: nil, momentumPhase: nil, isContinuous: false, flags: [])
    }
}

// MARK: - Modifier Key Handler

/// Helper class to manage modifier key reference counting and state
private class ModifierKeyState {
    /// Maps modifier mask to virtual key code
    static let maskToKeyCode: [UInt64: Int] = [
        CGEventFlags.maskCommand.rawValue: kVK_Command,
        CGEventFlags.maskAlternate.rawValue: kVK_Option,
        CGEventFlags.maskShift.rawValue: kVK_Shift,
        CGEventFlags.maskControl.rawValue: kVK_Control
    ]

    /// List of modifier masks in order for iteration
    static let modifierMasks: [CGEventFlags] = [
        .maskCommand, .maskAlternate, .maskShift, .maskControl
    ]
}


/// Service for simulating keyboard and mouse input via CGEvent
class InputSimulator: InputSimulatorProtocol, @unchecked Sendable {
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

    /// dedicated high-priority queue for key simulation (avoids blocking main thread with usleep)
    private let keyboardQueue = DispatchQueue(label: "com.xboxmapper.keyboard", qos: .userInteractive)
    
    /// Dedicated high-priority queue for mouse movement (avoids blocking by keyboard sleeps)
    private let mouseQueue = DispatchQueue(label: "com.xboxmapper.mouse", qos: .userInteractive)
    
    /// Lock for protecting shared state
    private let stateLock = NSLock()

    // MARK: - Keyboard Simulation

    /// Simulates a key press with optional modifiers
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags = []) {
        // Handle mouse button "key codes"
        if KeyCodeMapping.isMouseButton(keyCode) {
            pressMouseButton(keyCode)
            return
        }

        // Handle media key "key codes"
        if KeyCodeMapping.isMediaKey(keyCode) {
            pressMediaKey(keyCode)
            return
        }

        guard checkAccessibility() else { return }

        // Capture state needed for async execution safely
        stateLock.lock()
        let currentHeldModifiers = heldModifiers
        stateLock.unlock()
        
        let modifiersToPress = modifiers.subtracting(currentHeldModifiers)
        let startingFlags = currentHeldModifiers

        #if DEBUG
        print("🎮 Pressing key: \(keyCode) with modifiers: \(modifiers.rawValue) (Simulating: \(modifiersToPress.rawValue))")
        print("   Current held modifiers: \(currentHeldModifiers.rawValue)")
        #endif

        // Run key simulation on dedicated queue
        keyboardQueue.async { [weak self] in
            guard let self = self else { return }

            var currentFlags = startingFlags

            // Helper to press modifier
            func pressMod(_ key: Int, flag: CGEventFlags) {
                currentFlags.insert(flag)
                self.postKeyEvent(keyCode: CGKeyCode(key), keyDown: true, flags: currentFlags)
                usleep(Config.modifierPressDelay)
            }

            // Press modifier keys first (Command -> Shift -> Option -> Control)
            if modifiersToPress.contains(.maskCommand) { pressMod(kVK_Command, flag: .maskCommand) }
            if modifiersToPress.contains(.maskShift)   { pressMod(kVK_Shift,   flag: .maskShift) }
            if modifiersToPress.contains(.maskAlternate){ pressMod(kVK_Option,  flag: .maskAlternate) }
            if modifiersToPress.contains(.maskControl) { pressMod(kVK_Control, flag: .maskControl) }

            // Small delay after modifiers
            if !modifiersToPress.isEmpty {
                usleep(Config.postModifierDelay)
            }

            // Press the main key with all flags active
            self.postKeyEvent(keyCode: keyCode, keyDown: true, flags: currentFlags)
            usleep(Config.keyPressDuration)
            self.postKeyEvent(keyCode: keyCode, keyDown: false, flags: currentFlags)

            // Small delay before releasing modifiers
            if !modifiersToPress.isEmpty {
                usleep(Config.preReleaseDelay)
            }

            // Helper to release modifier
            func releaseMod(_ key: Int, flag: CGEventFlags) {
                currentFlags.remove(flag)
                self.postKeyEvent(keyCode: CGKeyCode(key), keyDown: false, flags: currentFlags)
                usleep(Config.modifierPressDelay)
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

        // Add special flags for arrow keys, function keys, etc.
        // These flags (Fn, NumPad) are required for apps like Rectangle to recognize shortcuts
        let specialFlags = specialKeyFlags(for: keyCode)
        let combinedFlags = flags.union(specialFlags)

        // Always set flags explicitly to override any inherited state from the event source
        // (e.g., prevents Fn/Globe key from being inherited from HID system state)
        event.flags = combinedFlags

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
        
        stateLock.lock()
        let currentHeld = heldModifiers
        stateLock.unlock()

        // Combine modifiers with special key flags (Fn, NumPad for arrows, etc.)
        let specialFlags = specialKeyFlags(for: keyCode)
        let combinedModifiers = modifiers.union(currentHeld).union(specialFlags)

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
        
        stateLock.lock()
        let currentHeld = heldModifiers
        stateLock.unlock()

        // Include special key flags on release as well
        let specialFlags = specialKeyFlags(for: keyCode)
        let combinedFlags = currentHeld.union(specialFlags)

        if let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            event.flags = combinedFlags
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Modifier Management

    /// Starts holding a modifier (for bumper/trigger modifier mappings)
    func holdModifier(_ modifier: CGEventFlags) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        stateLock.lock()
        defer { stateLock.unlock() }

        for mask in ModifierKeyState.modifierMasks where modifier.contains(mask) {
            let key = mask.rawValue
            let count = modifierCounts[key] ?? 0
            modifierCounts[key] = count + 1

            if count == 0 {
                // First time this modifier is being held
                heldModifiers.insert(mask)
                if let vKey = ModifierKeyState.maskToKeyCode[key] {
                    if let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKey), keyDown: true) {
                        event.flags = heldModifiers
                        event.post(tap: .cghidEventTap)
                    }
                }
            }
        }
    }

    /// Stops holding a modifier
    func releaseModifier(_ modifier: CGEventFlags) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        stateLock.lock()
        defer { stateLock.unlock() }

        for mask in ModifierKeyState.modifierMasks where modifier.contains(mask) {
            let key = mask.rawValue
            let count = modifierCounts[key] ?? 0
            if count > 0 {
                modifierCounts[key] = count - 1

                if count == 1 {
                    // Last button holding this modifier released
                    heldModifiers.remove(mask)
                    if let vKey = ModifierKeyState.maskToKeyCode[key] {
                        if let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKey), keyDown: false) {
                            event.flags = heldModifiers
                            event.post(tap: .cghidEventTap)
                        }
                    }
                }
            }
        }
    }

    /// Checks if we are currently holding the specified modifiers via controller
    func isHoldingModifiers(_ modifier: CGEventFlags) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !modifier.isEmpty && heldModifiers.contains(modifier)
    }

    /// Releases all held modifiers
    func releaseAllModifiers() {
        stateLock.lock()
        let currentHeld = heldModifiers
        stateLock.unlock()
        
        releaseModifier(currentHeld)
        
        stateLock.lock()
        // Reset all counts to zero
        for key in modifierCounts.keys {
            modifierCounts[key] = 0
        }
        heldModifiers = []
        stateLock.unlock()
    }

    // MARK: - Mouse Button State

    /// Tracks currently held mouse buttons to determine if moving should be a drag
    private var heldMouseButtons: Set<CGMouseButton> = []

    /// Tracks click timing for double/triple click detection
    private var lastClickTime: [CGMouseButton: Date] = [:]
    private var clickCounts: [CGMouseButton: Int64] = [:]

    /// Tracks sub-pixel movement residuals to prevent quantization stickiness
    private var residualMovement: CGPoint = .zero

    /// Cached union of all screen frames
    private var cachedScreenBounds: CGRect?
    /// Cached primary display height
    private var cachedPrimaryHeight: CGFloat?
    /// Cached accessibility state
    private var isAccessibilityTrusted: Bool = false
    
    init() {
        // .hidSystemState simulates hardware-level events, which are often more reliable for system shortcuts
        eventSource = CGEventSource(stateID: .hidSystemState)
        
        // Check accessibility once on init
        isAccessibilityTrusted = AXIsProcessTrusted()
        
        // Listen for screen changes to invalidate cache
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.stateLock.lock()
            self.cachedScreenBounds = nil
            self.cachedPrimaryHeight = nil
            self.stateLock.unlock()
        }
    }

    /// Check if we can post events (using cached state)
    private func checkAccessibility() -> Bool {
        if !isAccessibilityTrusted {
            // Re-check just in case user granted it recently
            isAccessibilityTrusted = AXIsProcessTrusted()
        }
        return isAccessibilityTrusted
    }

    /// Ensures screen bounds and height are cached. Must be called with stateLock held.
    private func ensureScreenCache() -> (CGRect, CGFloat) {
        if let bounds = cachedScreenBounds, let height = cachedPrimaryHeight {
            return (bounds, height)
        }

        // Use CoreGraphics APIs which are thread-safe (no main thread requirement)
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        var validFrame = CGRect.null

        // Get all active displays via CoreGraphics instead of NSScreen.screens
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        for display in displays {
            let displayBounds = CGDisplayBounds(display)
            validFrame = validFrame.union(displayBounds)
        }

        cachedScreenBounds = validFrame
        cachedPrimaryHeight = primaryHeight
        return (validFrame, primaryHeight)
    }

    // MARK: - Mouse Simulation

    /// Moves the mouse cursor by a delta
    func moveMouse(dx: CGFloat, dy: CGFloat) {
        // Dispatch to dedicated mouse queue
        mouseQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.checkAccessibility() else { return }
            guard let source = self.eventSource else { return }

            // Apply new delta to residual
            let totalDx = dx + self.residualMovement.x
            let totalDy = dy + self.residualMovement.y

            // Calculate integer pixels to move (rounding to nearest)
            let moveX = round(totalDx)
            let moveY = round(totalDy)

            // Update residual (keep the sub-pixel part)
            self.residualMovement = CGPoint(x: totalDx - moveX, y: totalDy - moveY)

            // If no pixel-level movement, skip to preserve residual for next frame
            if moveX == 0 && moveY == 0 { return }

            // Single lock acquisition for all state
            self.stateLock.lock()
            let heldButtons = self.heldMouseButtons
            let (bounds, primaryDisplayHeight) = self.ensureScreenCache()
            self.stateLock.unlock()

            let currentLocation = NSEvent.mouseLocation
            
            // Use cached primary display height for coordinate conversion
            // Convert from bottom-left origin to top-left origin
            let newX = currentLocation.x + moveX
            let newY = primaryDisplayHeight - currentLocation.y + moveY
            
            // Determine event type based on held buttons (drag if button held)
            let eventType: CGEventType
            let mouseButton: CGMouseButton
            
            if heldButtons.contains(.left) {
                eventType = .leftMouseDragged
                mouseButton = .left
            } else if heldButtons.contains(.right) {
                eventType = .rightMouseDragged
                mouseButton = .right
            } else if heldButtons.contains(.center) {
                eventType = .otherMouseDragged
                mouseButton = .center
            } else {
                eventType = .mouseMoved
                mouseButton = .left // Default for move events
            }

            // Clamp to valid screen bounds to avoid off-screen warps (which cause stickiness)
            let clampedX = max(bounds.minX, min(bounds.maxX - 1, newX))
            let clampedY = max(bounds.minY, min(bounds.maxY - 1, newY))
            let newPoint = CGPoint(x: clampedX, y: clampedY)

            // Warp the cursor first to bypass "sticky edges" when crossing screens
            _ = CGWarpMouseCursorPosition(newPoint)

            if let event = CGEvent(
                mouseEventSource: source,
                mouseType: eventType,
                mouseCursorPosition: newPoint,
                mouseButton: mouseButton
            ) {
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Scrolls by a delta
    func scroll(
        dx: CGFloat,
        dy: CGFloat,
        phase: CGScrollPhase?,
        momentumPhase: CGMomentumScrollPhase?,
        isContinuous: Bool,
        flags: CGEventFlags
    ) {
        mouseQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.checkAccessibility() else { return }
            guard let source = self.eventSource else { return }

            if let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(dy),
                wheel2: Int32(dx),
                wheel3: 0
            ) {
                if isContinuous {
                    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                    // Set instant mouser to 0 to indicate trackpad (not mouse)
                    event.setIntegerValueField(.scrollWheelEventInstantMouser, value: 0)
                    // Set point delta fields for native trackpad emulation
                    // Chrome and other browsers require these fields to recognize trackpad gestures
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
                    // Set fixed-point delta fields (16.16 fixed-point format)
                    // Native trackpads set these for precise sub-pixel scrolling
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
                    // Set scroll count to indicate this is a gesture event
                    event.setIntegerValueField(.scrollWheelEventScrollCount, value: 1)
                }
                if let phase {
                    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
                }
                if let momentumPhase {
                    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentumPhase.rawValue))
                }
                if flags.rawValue != 0 {
                    event.flags = flags
                }
                event.post(tap: .cghidEventTap)
            }
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
        let primaryDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        let cgLocation = CGPoint(x: location.x, y: primaryDisplayHeight - location.y)

        let (downType, button) = mouseEventType(for: keyCode, down: true)
        
        stateLock.lock()
        defer { stateLock.unlock() }

        // Track hold state
        heldMouseButtons.insert(button)

        // Calculate click count for double/triple click support
        let now = Date()
        let clickCount: Int64
        if let lastTime = lastClickTime[button],
           now.timeIntervalSince(lastTime) < Config.multiClickThreshold {
            // Within threshold - increment click count
            clickCount = (clickCounts[button] ?? 0) + 1
        } else {
            // Outside threshold - reset to single click
            clickCount = 1
        }
        clickCounts[button] = clickCount
        lastClickTime[button] = now

        if let event = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: cgLocation,
            mouseButton: button
        ) {
            // Set click count for double/triple click recognition
            event.setIntegerValueField(.mouseEventClickState, value: clickCount)
            event.post(tap: .cghidEventTap)
        }
    }

    private func mouseButtonUp(_ keyCode: CGKeyCode) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let location = NSEvent.mouseLocation
        let primaryDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        let cgLocation = CGPoint(x: location.x, y: primaryDisplayHeight - location.y)

        let (upType, button) = mouseEventType(for: keyCode, down: false)

        stateLock.lock()
        defer { stateLock.unlock() }

        // Update hold state
        heldMouseButtons.remove(button)

        // Use the same click count as the down event
        let clickCount = clickCounts[button] ?? 1

        if let event = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: cgLocation,
            mouseButton: button
        ) {
            // Set click count to match down event for proper double/triple click
            event.setIntegerValueField(.mouseEventClickState, value: clickCount)
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

    // MARK: - Media Key Simulation

    /// NX key type constants for media keys
    private enum NXKeyType: UInt32 {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case play = 16
        case next = 17
        case previous = 18
        case fast = 19
        case rewind = 20
    }

    private func pressMediaKey(_ keyCode: CGKeyCode) {
        guard let nxKeyType = mediaKeyToNXType(keyCode) else {
            #if DEBUG
            print("❌ Unknown media key code: \(keyCode)")
            #endif
            return
        }

        keyboardQueue.async {
            self.postMediaKeyEvent(keyType: nxKeyType, keyDown: true)
            usleep(50000)  // 50ms hold
            self.postMediaKeyEvent(keyType: nxKeyType, keyDown: false)
        }
    }

    private func mediaKeyToNXType(_ keyCode: CGKeyCode) -> NXKeyType? {
        switch keyCode {
        case KeyCodeMapping.mediaPlayPause: return .play
        case KeyCodeMapping.mediaNext: return .next
        case KeyCodeMapping.mediaPrevious: return .previous
        case KeyCodeMapping.mediaFastForward: return .fast
        case KeyCodeMapping.mediaRewind: return .rewind
        case KeyCodeMapping.volumeUp: return .soundUp
        case KeyCodeMapping.volumeDown: return .soundDown
        case KeyCodeMapping.volumeMute: return .mute
        case KeyCodeMapping.brightnessUp: return .brightnessUp
        case KeyCodeMapping.brightnessDown: return .brightnessDown
        default: return nil
        }
    }

    private func postMediaKeyEvent(keyType: NXKeyType, keyDown: Bool) {
        // NX media key events use NSEvent with subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS)
        // data1 format: (keyCode << 16) | (flags << 8) | repeat
        // flags: 0x0A = key down, 0x0B = key up
        let keyCode = Int(keyType.rawValue)
        let flags = keyDown ? 0x0A : 0x0B
        let data1 = (keyCode << 16) | (flags << 8)

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: data1,
            data2: -1
        ) else { return }

        event.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - Mapping Execution

    /// Executes a key mapping (does a full press+release cycle)
    func executeMapping(_ mapping: KeyMapping) {
        #if DEBUG
        print("📋 executeMapping called:")
        print("   keyCode: \(mapping.keyCode?.description ?? "nil")")
        print("   modifiers - cmd:\(mapping.modifiers.command) opt:\(mapping.modifiers.option) shift:\(mapping.modifiers.shift) ctrl:\(mapping.modifiers.control)")
        print("   cgEventFlags: \(mapping.modifiers.cgEventFlags.rawValue)")
        print("   isHoldModifier: \(mapping.isHoldModifier)")
        #endif

        if let keyCode = mapping.keyCode {
            // For any mapping with a key code, do a full press (handles both regular keys and mouse buttons)
            pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            // Modifier-only mapping - tap the modifiers
            let flags = mapping.modifiers.cgEventFlags
            holdModifier(flags)
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.modifierReleaseCheckDelay) { [weak self] in
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
    
    // MARK: - Macro Execution
    
    func executeMacro(_ macro: Macro) {
        keyboardQueue.async { [weak self] in
            guard let self = self else { return }
            
            for step in macro.steps {
                switch step {
                case .press(let mapping):
                    self.pressKeyMapping(mapping)

                case .hold(let mapping, let duration):
                    self.holdKeyMapping(mapping, duration: duration)

                case .delay(let duration):
                    usleep(useconds_t(duration * 1_000_000))

                case .typeText(let text, let speed):
                    self.typeString(text, speed: speed)

                case .openApp(let bundleIdentifier, let newWindow):
                    self.openApplication(bundleIdentifier: bundleIdentifier, newWindow: newWindow)

                case .openLink(let url):
                    self.openURL(url)
                }
            }
        }
    }
    
    private func pressKeyMapping(_ mapping: KeyMapping) {
        if let keyCode = mapping.keyCode {
            pressKey(keyCode, modifiers: mapping.modifiers.cgEventFlags)
        } else if mapping.modifiers.hasAny {
            let flags = mapping.modifiers.cgEventFlags
            holdModifier(flags)
            usleep(Config.keyPressDuration)
            releaseModifier(flags)
        }
    }
    
    private func holdKeyMapping(_ mapping: KeyMapping, duration: TimeInterval) {
        if let keyCode = mapping.keyCode {
            keyDown(keyCode, modifiers: mapping.modifiers.cgEventFlags)
            usleep(useconds_t(duration * 1_000_000))
            keyUp(keyCode)
        } else if mapping.modifiers.hasAny {
            let flags = mapping.modifiers.cgEventFlags
            holdModifier(flags)
            usleep(useconds_t(duration * 1_000_000))
            releaseModifier(flags)
        }
    }
    
    private func typeString(_ text: String, speed: Int) {
        // 0 = Paste (Instant)
        if speed == 0 {
            pasteString(text)
            return
        }
        
        guard let source = eventSource else { return }
        
        // Calculate delay in microseconds
        // CPM (Chars Per Minute) -> Chars Per Second = CPM / 60
        // Seconds Per Char = 60 / CPM
        // Microseconds = (60 / CPM) * 1_000_000
        let charDelayUs = useconds_t((60.0 / Double(speed)) * 1_000_000)
        
        for char in text {
            // Create a unicode event
            var chars = [UniChar(String(char).utf16.first!)]
            
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                event.post(tap: .cghidEventTap)
            }
            
            usleep(Config.keyPressDuration)
            
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                event.post(tap: .cghidEventTap)
            }
            
            usleep(charDelayUs)
        }
    }
    
    private func pasteString(_ text: String) {
        // Use clipboard for instant paste
        // NSPasteboard must be accessed from the main thread
        DispatchQueue.main.async {
            // 1. Save current clipboard
            let pasteboard = NSPasteboard.general
            // We can't reliably copy old items without potentially blocking or issues, so we skip restoring for now
            // Or we could try to just clear and set.

            // 2. Set new text
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }

        // Wait briefly for clipboard update
        usleep(50000) // 50ms

        // 3. Cmd+V
        pressKey(CGKeyCode(kVK_ANSI_V), modifiers: .maskCommand)

        // 4. Restore clipboard - skipped for stability
    }

    private func openApplication(bundleIdentifier: String, newWindow: Bool) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSLog("[Macro] App not found: \(bundleIdentifier)")
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        let config = NSWorkspace.OpenConfiguration()

        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error = error {
                    NSLog("[Macro] Failed to open app: \(error.localizedDescription)")
                }
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 3.0)

        if newWindow {
            // Wait for app to be ready, then send Cmd+N
            usleep(300_000)
            pressKey(CGKeyCode(kVK_ANSI_N), modifiers: .maskCommand)
        }
    }

    private func openURL(_ urlString: String) {
        var resolved = urlString
        if !resolved.contains("://") {
            resolved = "https://" + resolved
        }
        guard let url = URL(string: resolved) else {
            NSLog("[Macro] Invalid URL: \(urlString)")
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2.0)

        // Small delay to let the browser handle the URL
        usleep(200_000)
    }
}

// Import Carbon for key codes
import Carbon.HIToolbox

private let kVK_Command = 0x37
private let kVK_Shift = 0x38
private let kVK_Option = 0x3A
private let kVK_Control = 0x3B

// Arrow key codes
private let kVK_LeftArrow: CGKeyCode = 0x7B
private let kVK_RightArrow: CGKeyCode = 0x7C
private let kVK_DownArrow: CGKeyCode = 0x7D
private let kVK_UpArrow: CGKeyCode = 0x7E

// Function key codes
private let kVK_F1: CGKeyCode = 0x7A
private let kVK_F2: CGKeyCode = 0x78
private let kVK_F3: CGKeyCode = 0x63
private let kVK_F4: CGKeyCode = 0x76
private let kVK_F5: CGKeyCode = 0x60
private let kVK_F6: CGKeyCode = 0x61
private let kVK_F7: CGKeyCode = 0x62
private let kVK_F8: CGKeyCode = 0x64
private let kVK_F9: CGKeyCode = 0x65
private let kVK_F10: CGKeyCode = 0x6D
private let kVK_F11: CGKeyCode = 0x67
private let kVK_F12: CGKeyCode = 0x6F
private let kVK_F13: CGKeyCode = 0x69
private let kVK_F14: CGKeyCode = 0x6B
private let kVK_F15: CGKeyCode = 0x71
private let kVK_F16: CGKeyCode = 0x6A
private let kVK_F17: CGKeyCode = 0x40
private let kVK_F18: CGKeyCode = 0x4F
private let kVK_F19: CGKeyCode = 0x50
private let kVK_F20: CGKeyCode = 0x5A

// Navigation keys
private let kVK_Home: CGKeyCode = 0x73
private let kVK_End: CGKeyCode = 0x77
private let kVK_PageUp: CGKeyCode = 0x74
private let kVK_PageDown: CGKeyCode = 0x79
private let kVK_ForwardDelete: CGKeyCode = 0x75

/// Keys that require NumPad and/or Fn flags to be recognized properly by apps
private let numPadKeys: Set<CGKeyCode> = [
    kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow,
    kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete
]

/// Keys that require the Fn flag
private let fnKeys: Set<CGKeyCode> = [
    kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
    kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
    kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow
]

/// Returns additional flags needed for special keys (arrow keys, function keys, etc.)
private func specialKeyFlags(for keyCode: CGKeyCode) -> CGEventFlags {
    var flags: CGEventFlags = []

    if numPadKeys.contains(keyCode) {
        flags.insert(.maskNumericPad)
    }
    if fnKeys.contains(keyCode) {
        flags.insert(.maskSecondaryFn)
    }

    return flags
}
