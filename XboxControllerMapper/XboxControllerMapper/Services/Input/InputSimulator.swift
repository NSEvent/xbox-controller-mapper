import Foundation
import CoreGraphics
import AppKit
import IOKit.hidsystem
import ApplicationServices.HIServices

protocol InputSimulatorProtocol: Sendable {
    func pressKey(_ keyCode: CGKeyCode, modifiers: CGEventFlags)
    func keyDown(_ keyCode: CGKeyCode, modifiers: CGEventFlags)
    func keyUp(_ keyCode: CGKeyCode)
    func holdModifier(_ modifier: CGEventFlags)
    func releaseModifier(_ modifier: CGEventFlags)
    func releaseAllModifiers()
    func isHoldingModifiers(_ modifier: CGEventFlags) -> Bool
    func getHeldModifiers() -> CGEventFlags
    func moveMouse(dx: CGFloat, dy: CGFloat)
    func moveMouseNative(dx: Int, dy: Int)
    func warpMouseTo(point: CGPoint)
    var isLeftMouseButtonHeld: Bool { get }
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
    /// Static tracked cursor position for use by other services (e.g., ActionFeedbackIndicator)
    /// when Accessibility Zoom is active. Access via getTrackedCursorPosition().
    private static var sharedTrackedPosition: CGPoint?
    private static var sharedLastMoveTime: Date = .distantPast
    private static var sharedLock = NSLock()

    /// Accumulated movement delta since last consumption (for hint positioning during zoom)
    private static var accumulatedDelta: CGPoint = .zero

    /// Returns the tracked cursor position if available and Accessibility Zoom is active,
    /// otherwise returns nil (caller should fall back to NSEvent.mouseLocation)
    static func getTrackedCursorPosition() -> CGPoint? {
        guard UAZoomEnabled() else { return nil }
        sharedLock.lock()
        defer { sharedLock.unlock() }
        return sharedTrackedPosition
    }

    /// Returns true if cursor was moved very recently by the controller
    /// (movement within last 50ms). Used by ActionFeedbackIndicator to briefly
    /// pause position updates right after movement when Accessibility Zoom is active.
    /// The short 50ms window skips the immediate unreliable reading but allows
    /// frequent updates to follow the cursor during long drags.
    static func isCursorBeingMoved() -> Bool {
        sharedLock.lock()
        defer { sharedLock.unlock() }
        return Date().timeIntervalSince(sharedLastMoveTime) < 0.05
    }

    /// Consumes and returns the accumulated movement delta since last call.
    /// Used by ActionFeedbackIndicator to apply relative movement during zoom.
    /// Delta is in screen points (positive X = right, positive Y = down in CG coords).
    static func consumeMovementDelta() -> CGPoint {
        sharedLock.lock()
        let delta = accumulatedDelta
        accumulatedDelta = .zero
        sharedLock.unlock()
        return delta
    }

    /// Resets the accumulated movement delta without consuming it.
    /// Called when resyncing hint position to absolute coordinates.
    static func resetMovementDelta() {
        sharedLock.lock()
        accumulatedDelta = .zero
        sharedLock.unlock()
    }

    /// Returns the current Accessibility Zoom level (1.0 = no zoom, 2.0 = 2x zoom, etc.)
    static func getZoomLevel() -> CGFloat {
        CGFloat(UserDefaults(suiteName: "com.apple.universalaccess")?.double(forKey: "closeViewZoomFactor") ?? 1.0)
    }

    /// Updates the shared tracked position (called from moveMouse)
    private static func updateSharedTrackedPosition(_ point: CGPoint?, delta: CGPoint = .zero) {
        sharedLock.lock()
        sharedTrackedPosition = point
        sharedLastMoveTime = Date()
        accumulatedDelta.x += delta.x
        accumulatedDelta.y += delta.y
        sharedLock.unlock()
    }
    private let eventSource: CGEventSource?

    /// Handler for executing system commands from macro steps
    var systemCommandHandler: (@Sendable (SystemCommand) -> Void)?

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

    /// Returns the currently held modifier flags
    func getHeldModifiers() -> CGEventFlags {
        stateLock.lock()
        defer { stateLock.unlock() }
        return heldModifiers
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

    /// Thread-safe check if left mouse button is currently held
    var isLeftMouseButtonHeld: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return heldMouseButtons.contains(.left)
    }

    /// Tracks click timing for double/triple click detection
    private var lastClickTime: [CGMouseButton: Date] = [:]
    private var clickCounts: [CGMouseButton: Int64] = [:]

    /// Monotonically increasing mouse event number shared across mouseDown/mouseDragged/mouseUp.
    /// Real hardware assigns the same event number to a mouseDown and its matching mouseUp, with
    /// all intervening mouseDragged events also sharing that number. System tools like screencapture
    /// use this field to correlate a down-drag-up sequence into a single continuous gesture.
    private var mouseEventNumber: Int64 = 0

    /// Tracks sub-pixel movement residuals to prevent quantization stickiness
    private var residualMovement: CGPoint = .zero

    /// Tracked cursor position for Accessibility Zoom compatibility
    /// When zoom is active, reading cursor position from the system can return transformed
    /// coordinates that cause "reset" behavior. We track position internally instead.
    private var trackedCursorPosition: CGPoint?
    /// Last time we synced the tracked position with the system (for drift correction)
    private var lastCursorSyncTime: Date = .distantPast
    /// Last time moveMouse was called (to detect inactivity and clear tracked position)
    private var lastMouseMoveTime: Date = .distantPast

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
            let eventNumber = self.mouseEventNumber
            let (bounds, primaryDisplayHeight) = self.ensureScreenCache()

            // Use tracked position if available, otherwise sync from system
            // This prevents Accessibility Zoom coordinate transformations from causing
            // cursor "reset" behavior when reading position each frame
            let now = Date()
            let zoomActive = UAZoomEnabled()
            let currentCGPoint: CGPoint

            // If there's been no movement for 2+ seconds, clear tracked position
            // This ensures we re-sync if user moved cursor with physical trackpad
            if now.timeIntervalSince(self.lastMouseMoveTime) > 2.0 {
                self.trackedCursorPosition = nil
            }
            self.lastMouseMoveTime = now

            if let tracked = self.trackedCursorPosition {
                // When zoom is active, always use tracked position (never sync during movement)
                // When zoom is inactive, sync every 0.5s for drift correction
                if zoomActive || now.timeIntervalSince(self.lastCursorSyncTime) < 0.5 {
                    currentCGPoint = tracked
                } else {
                    // Zoom inactive and timeout expired - sync from system
                    if let locationEvent = CGEvent(source: nil) {
                        currentCGPoint = locationEvent.location
                    } else {
                        let nsLocation = NSEvent.mouseLocation
                        currentCGPoint = CGPoint(
                            x: nsLocation.x,
                            y: primaryDisplayHeight - nsLocation.y
                        )
                    }
                    self.lastCursorSyncTime = now
                }
            } else {
                // No tracked position - sync from system (first movement or after inactivity)
                if let locationEvent = CGEvent(source: nil) {
                    currentCGPoint = locationEvent.location
                } else {
                    let nsLocation = NSEvent.mouseLocation
                    currentCGPoint = CGPoint(
                        x: nsLocation.x,
                        y: primaryDisplayHeight - nsLocation.y
                    )
                }
                self.lastCursorSyncTime = now
            }
            self.stateLock.unlock()

            let newX = currentCGPoint.x + moveX
            let newY = currentCGPoint.y + moveY

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

            // Clamp to valid screen bounds
            let clampedX = max(bounds.minX, min(bounds.maxX - 1, newX))
            let clampedY = max(bounds.minY, min(bounds.maxY - 1, newY))
            let newPoint = CGPoint(x: clampedX, y: clampedY)

            let isDrag = eventType != .mouseMoved

            // During drags, do NOT call CGWarpMouseCursorPosition. The warp resets
            // macOS internal mouse-button-down state, which breaks drag correlation
            // for system tools like screencapture. The CGEvent with mouseCursorPosition
            // already moves the cursor to the correct location.
            if !isDrag {
                // Set suppression interval to 0 to prevent 250ms freeze after warp
                if let warpSource = CGEventSource(stateID: .combinedSessionState) {
                    warpSource.localEventsSuppressionInterval = 0.0
                }
                _ = CGWarpMouseCursorPosition(newPoint)
            }

            // Update tracked position to avoid reading back transformed coordinates
            self.stateLock.lock()
            self.trackedCursorPosition = newPoint
            self.stateLock.unlock()

            // Update shared position for other services (e.g., ActionFeedbackIndicator)
            // Pass the movement delta for relative positioning during zoom
            Self.updateSharedTrackedPosition(newPoint, delta: CGPoint(x: moveX, y: moveY))

            // If Accessibility Zoom is enabled, tell it to focus on the new cursor position
            // This helps the zoom viewport follow the cursor movement
            if UAZoomEnabled() {
                var focusRect = CGRect(x: newPoint.x - 1, y: newPoint.y - 1, width: 2, height: 2)
                UAZoomChangeFocus(&focusRect, nil, UAZoomChangeFocusType(kUAZoomFocusTypeOther))
            }

            if let event = CGEvent(
                mouseEventSource: source,
                mouseType: eventType,
                mouseCursorPosition: newPoint,
                mouseButton: mouseButton
            ) {
                // Set delta fields for Accessibility Zoom viewport panning
                event.setIntegerValueField(.mouseEventDeltaX, value: Int64(moveX))
                event.setIntegerValueField(.mouseEventDeltaY, value: Int64(moveY))
                // For drag events, set the same event number as the originating mouseDown
                // and pressure so system tools (screencapture, etc.) recognize the drag
                // as part of a continuous down-drag-up gesture.
                if isDrag {
                    event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
                    event.setDoubleValueField(.mouseEventPressure, value: 1.0)
                }
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Moves the mouse cursor by posting a CGEvent with delta fields at the HID event tap.
    /// This lets macOS apply its native pointer acceleration, matching real trackpad feel.
    func moveMouseNative(dx: Int, dy: Int) {
        mouseQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.checkAccessibility() else { return }
            guard dx != 0 || dy != 0 else { return }

            self.stateLock.lock()
            let heldButtons = self.heldMouseButtons
            let eventNumber = self.mouseEventNumber
            self.stateLock.unlock()

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
                mouseButton = .left
            }

            // Get current cursor position for the event location
            let cursorPos: CGPoint
            if let locEvent = CGEvent(source: nil) {
                cursorPos = locEvent.location
            } else {
                let ns = NSEvent.mouseLocation
                let screenH = NSScreen.main?.frame.height ?? 1080
                cursorPos = CGPoint(x: ns.x, y: screenH - ns.y)
            }

            guard let event = CGEvent(
                mouseEventSource: self.eventSource,
                mouseType: eventType,
                mouseCursorPosition: cursorPos,
                mouseButton: mouseButton
            ) else { return }

            event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
            // For drag events, set the same event number as the originating mouseDown
            // and pressure so system tools (screencapture, etc.) recognize the drag.
            if eventType != .mouseMoved {
                event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
                event.setDoubleValueField(.mouseEventPressure, value: 1.0)
            }
            event.post(tap: .cghidEventTap)
        }
    }

    /// Warps the mouse cursor to an absolute position (Quartz coordinates) and resets tracking.
    /// Used after swipe typing ends to move the real cursor to where the swipe cursor was.
    func warpMouseTo(point: CGPoint) {
        mouseQueue.async { [weak self] in
            guard let self = self else { return }
            if let source = CGEventSource(stateID: .combinedSessionState) {
                source.localEventsSuppressionInterval = 0.0
            }
            _ = CGWarpMouseCursorPosition(point)
            self.stateLock.lock()
            self.trackedCursorPosition = point
            self.lastMouseMoveTime = Date()
            self.lastCursorSyncTime = Date()
            self.stateLock.unlock()
        }
    }

    /// Accumulated scroll delta for Accessibility Zoom (Control+scroll -> keyboard shortcut conversion)
    private var accessibilityZoomAccumulator: CGFloat = 0
    /// Threshold for triggering a zoom step (in scroll pixels)
    private let accessibilityZoomThreshold: CGFloat = 10.0
    /// Last time we sent a zoom keyboard shortcut (for rate limiting)
    private var lastAccessibilityZoomTime: Date = .distantPast
    /// Minimum interval between zoom keyboard shortcuts
    private let accessibilityZoomMinInterval: TimeInterval = 0.05
    /// Counter for Control+scroll zoom attempts
    private var zoomAttemptCount: Int = 0
    /// Whether we've ever seen zoom level above 1.0 (proves shortcuts are working)
    private var hasEverSeenZoomActive: Bool = false
    /// Whether we've already shown the keyboard shortcuts warning
    private var hasShownZoomKeyboardShortcutWarning: Bool = false

    /// Scrolls by a delta
    func scroll(
        dx: CGFloat,
        dy: CGFloat,
        phase: CGScrollPhase?,
        momentumPhase: CGMomentumScrollPhase?,
        isContinuous: Bool,
        flags: CGEventFlags
    ) {
        // Check if Control is held - if so, convert to Accessibility Zoom keyboard shortcuts
        // macOS Accessibility Zoom doesn't respond to synthetic Control+scroll events,
        // but does respond to Option+Command+Plus/Minus keyboard shortcuts
        if flags.contains(.maskControl) && dy != 0 {
            handleAccessibilityZoom(dy: dy)
            return
        }

        mouseQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.checkAccessibility() else { return }

            if let event = CGEvent(
                scrollWheelEvent2Source: self.eventSource,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(dy),
                wheel2: Int32(dx),
                wheel3: 0
            ) {
                if isContinuous {
                    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                    event.setIntegerValueField(.scrollWheelEventInstantMouser, value: 0)
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(dx))
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
                    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
                }
                if let phase {
                    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
                }
                if let momentumPhase {
                    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentumPhase.rawValue))
                }
                // Set modifier flags on the scroll event (excluding Control which was handled above)
                let scrollFlags = flags.subtracting(.maskControl)
                if scrollFlags.rawValue != 0 {
                    event.flags = event.flags.union(scrollFlags)
                }
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// Handles Accessibility Zoom by converting Control+scroll to Option+Command+Plus/Minus
    private func handleAccessibilityZoom(dy: CGFloat) {
        // Accumulate scroll delta
        accessibilityZoomAccumulator += dy

        // Check if we've accumulated enough for a zoom step
        guard abs(accessibilityZoomAccumulator) >= accessibilityZoomThreshold else { return }

        // Rate limit keyboard shortcut sending
        let now = Date()
        guard now.timeIntervalSince(lastAccessibilityZoomTime) >= accessibilityZoomMinInterval else { return }

        // Determine zoom direction: positive dy = scroll up = zoom in
        let zoomIn = accessibilityZoomAccumulator > 0

        // Reset accumulator
        accessibilityZoomAccumulator = 0
        lastAccessibilityZoomTime = now

        // Check if zoom is working before sending shortcut
        // If we've ever seen zoom active (level > 1.0 or UAZoomEnabled), shortcuts work
        if !hasEverSeenZoomActive {
            if UAZoomEnabled() || getCurrentZoomLevel() > 1.001 {
                hasEverSeenZoomActive = true
            } else if !hasShownZoomKeyboardShortcutWarning {
                zoomAttemptCount += 1
                // After 5 attempts with no zoom activity, show warning and stop sending shortcuts
                if zoomAttemptCount >= 5 {
                    hasShownZoomKeyboardShortcutWarning = true
                    showZoomKeyboardShortcutWarning()
                    return // Don't send shortcuts that won't work
                }
            } else {
                // Warning was already shown and zoom still not working - don't send shortcuts
                return
            }
        }

        // Send zoom keyboard shortcut on keyboard queue
        // Option+Command+= (zoom in) or Option+Command+- (zoom out)
        keyboardQueue.async { [weak self] in
            guard let self = self else { return }

            // kVK_ANSI_Equal = 0x18 = 24, kVK_ANSI_Minus = 0x1B = 27
            let keyCode: CGKeyCode = zoomIn ? 24 : 27
            let modifiers: CGEventFlags = [.maskAlternate, .maskCommand]

            // Press the key with modifiers
            if let downEvent = CGEvent(keyboardEventSource: self.eventSource, virtualKey: keyCode, keyDown: true) {
                downEvent.flags = modifiers
                downEvent.post(tap: .cghidEventTap)
            }

            usleep(10000) // 10ms hold

            if let upEvent = CGEvent(keyboardEventSource: self.eventSource, virtualKey: keyCode, keyDown: false) {
                upEvent.flags = modifiers
                upEvent.post(tap: .cghidEventTap)
            }
        }
    }

    /// Gets the current Accessibility Zoom level from user defaults
    private func getCurrentZoomLevel() -> Double {
        UserDefaults(suiteName: "com.apple.universalaccess")?.double(forKey: "closeViewZoomFactor") ?? 1.0
    }

    /// Resets zoom detection state so shortcuts will be tried again
    /// Called when user opens Settings to enable keyboard shortcuts
    private func resetZoomDetectionState() {
        zoomAttemptCount = 0
        hasShownZoomKeyboardShortcutWarning = false
        // Don't reset hasEverSeenZoomActive - if it was working before, it should still work
    }

    /// Shows a warning that keyboard shortcuts need to be enabled for Accessibility Zoom
    private func showZoomKeyboardShortcutWarning() {
        DispatchQueue.main.async {
            // Create a non-modal floating panel instead of blocking alert
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 200),
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "ControllerKeys"
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false

            let contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))

            // App icon
            if let appIcon = NSApp.applicationIconImage {
                let iconView = NSImageView(frame: NSRect(x: 20, y: 110, width: 64, height: 64))
                iconView.image = appIcon
                contentView.addSubview(iconView)
            }

            // Title
            let titleField = NSTextField(labelWithString: "Enable Keyboard Shortcuts for Zoom")
            titleField.frame = NSRect(x: 94, y: 150, width: 340, height: 24)
            titleField.font = NSFont.boldSystemFont(ofSize: 14)
            titleField.isEditable = false
            titleField.isBordered = false
            titleField.backgroundColor = .clear
            contentView.addSubview(titleField)

            // Message
            let textField = NSTextField(wrappingLabelWithString:
                "To use Control+Scroll for Accessibility Zoom with your controller, enable \"Use keyboard shortcuts to zoom\" in System Settings.\n\nSystem Settings → Accessibility → Zoom"
            )
            textField.frame = NSRect(x: 94, y: 55, width: 340, height: 90)
            textField.isEditable = false
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.font = NSFont.systemFont(ofSize: 12)
            contentView.addSubview(textField)

            // Buttons - properly spaced
            let dismissButton = NSButton(title: "Dismiss", target: nil, action: nil)
            dismissButton.frame = NSRect(x: 220, y: 15, width: 100, height: 32)
            dismissButton.bezelStyle = .rounded
            dismissButton.keyEquivalent = "\u{1b}" // Escape
            contentView.addSubview(dismissButton)

            let openButton = NSButton(title: "Open Settings", target: nil, action: nil)
            openButton.frame = NSRect(x: 330, y: 15, width: 110, height: 32)
            openButton.bezelStyle = .rounded
            openButton.keyEquivalent = "\r"
            contentView.addSubview(openButton)

            panel.contentView = contentView
            panel.center()

            // Use a simple approach - just make the panel orderable and let user interact
            panel.orderFrontRegardless()

            // Store reference to prevent deallocation and set up click handlers
            objc_setAssociatedObject(panel, "keepAlive", panel, .OBJC_ASSOCIATION_RETAIN)

            // Use block-based approach for button actions
            class ButtonHandler: NSObject {
                let panel: NSPanel
                let onOpenSettings: () -> Void
                init(panel: NSPanel, onOpenSettings: @escaping () -> Void) {
                    self.panel = panel
                    self.onOpenSettings = onOpenSettings
                }
                @objc func openSettings() {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Zoom") {
                        NSWorkspace.shared.open(url)
                    }
                    onOpenSettings()
                    panel.close()
                }
                @objc func dismiss() {
                    panel.close()
                }
            }
            let handler = ButtonHandler(panel: panel) { [weak self] in
                // Reset state so zoom shortcuts will be tried again after user enables setting
                self?.resetZoomDetectionState()
            }
            objc_setAssociatedObject(panel, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
            openButton.target = handler
            openButton.action = #selector(ButtonHandler.openSettings)
            dismissButton.target = handler
            dismissButton.action = #selector(ButtonHandler.dismiss)
        }
    }

    // MARK: - Mouse Button Simulation

    private func pressMouseButton(_ keyCode: CGKeyCode) {
        // Both down and up dispatch to the serial mouseQueue, maintaining order
        mouseButtonDown(keyCode)
        mouseButtonUp(keyCode)
    }

    private func mouseButtonDown(_ keyCode: CGKeyCode) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let (downType, button) = mouseEventType(for: keyCode, down: true)

        // Dispatch on mouseQueue so mouse button events and drag events from
        // moveMouse are properly ordered on the same serial queue. Without this,
        // mouseDown (from input queue) and leftMouseDragged (from mouseQueue)
        // can arrive out of order, causing system tools like screencapture to
        // miss the drag sequence entirely.
        mouseQueue.async { [weak self] in
            guard let self = self else { return }

            self.stateLock.lock()

            let cgLocation = self.resolveClickLocationLocked(now: Date())

            // Track hold state
            self.heldMouseButtons.insert(button)

            // Assign a new event number for this down-drag-up sequence.
            // All subsequent mouseDragged and mouseUp events will reuse this number,
            // which is how macOS correlates them into a single gesture (required by
            // system tools like screencapture).
            self.mouseEventNumber += 1
            let eventNumber = self.mouseEventNumber

            // Calculate click count for double/triple click support
            let now = Date()
            let clickCount: Int64
            if let lastTime = self.lastClickTime[button],
               now.timeIntervalSince(lastTime) < Config.multiClickThreshold {
                clickCount = (self.clickCounts[button] ?? 0) + 1
            } else {
                clickCount = 1
            }
            self.clickCounts[button] = clickCount
            self.lastClickTime[button] = now

            self.stateLock.unlock()

            if let event = CGEvent(
                mouseEventSource: source,
                mouseType: downType,
                mouseCursorPosition: cgLocation,
                mouseButton: button
            ) {
                event.setIntegerValueField(.mouseEventClickState, value: clickCount)
                event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
                // Set pressure so system tools (screencapture, etc.) recognize the click
                event.setDoubleValueField(.mouseEventPressure, value: 1.0)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func mouseButtonUp(_ keyCode: CGKeyCode) {
        guard checkAccessibility() else { return }
        guard let source = eventSource else { return }

        let (upType, button) = mouseEventType(for: keyCode, down: false)

        mouseQueue.async { [weak self] in
            guard let self = self else { return }

            self.stateLock.lock()

            let cgLocation = self.resolveClickLocationLocked(now: Date())

            // Update hold state
            self.heldMouseButtons.remove(button)

            // Use the same click count and event number as the down event
            let clickCount = self.clickCounts[button] ?? 1
            let eventNumber = self.mouseEventNumber

            self.stateLock.unlock()

            if let event = CGEvent(
                mouseEventSource: source,
                mouseType: upType,
                mouseCursorPosition: cgLocation,
                mouseButton: button
            ) {
                event.setIntegerValueField(.mouseEventClickState, value: clickCount)
                event.setIntegerValueField(.mouseEventNumber, value: eventNumber)
                event.setDoubleValueField(.mouseEventPressure, value: 0.0)
                event.post(tap: .cghidEventTap)
            }
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

    /// Resolves click location while `stateLock` is held.
    private func resolveClickLocationLocked(now: Date) -> CGPoint {
        let fallbackLocation = NSEvent.mouseLocation
        let primaryDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        return MouseClickLocationPolicy.resolve(
            zoomActive: UAZoomEnabled(),
            trackedCursorPosition: trackedCursorPosition,
            lastControllerMoveTime: lastMouseMoveTime,
            fallbackMouseLocation: fallbackLocation,
            primaryDisplayHeight: primaryDisplayHeight,
            now: now,
            trackedCursorMaxAge: Config.zoomTrackedClickMaxAge
        )
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

                case .typeText(let text, let speed, let pressEnter):
                    self.typeString(text, speed: speed)
                    if pressEnter {
                        self.pressKey(36, modifiers: []) // 36 = Return key
                    }

                case .openApp(let bundleIdentifier, let newWindow):
                    self.openApplication(bundleIdentifier: bundleIdentifier, newWindow: newWindow)

                case .openLink(let url):
                    self.openURL(url)

                case .shellCommand(let command, let inTerminal):
                    let systemCommand = SystemCommand.shellCommand(command: command, inTerminal: inTerminal)
                    self.systemCommandHandler?(systemCommand)

                case .webhook(let url, let method, let headers, let body):
                    let systemCommand = SystemCommand.httpRequest(url: url, method: method, headers: headers, body: body)
                    self.systemCommandHandler?(systemCommand)

                case .obsWebSocket(let url, let password, let requestType, let requestData):
                    let systemCommand = SystemCommand.obsWebSocket(url: url, password: password, requestType: requestType, requestData: requestData)
                    self.systemCommandHandler?(systemCommand)
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

        // Use nil source to avoid inheriting HID system modifier state
        // This ensures typed characters aren't affected by held controller buttons

        // Calculate delay in microseconds
        // CPM (Chars Per Minute) -> Chars Per Second = CPM / 60
        // Seconds Per Char = 60 / CPM
        // Microseconds = (60 / CPM) * 1_000_000
        let charDelayUs = useconds_t((60.0 / Double(speed)) * 1_000_000)

        for char in text {
            // Create a unicode event with nil source (no inherited modifier state)
            guard let firstUTF16 = String(char).utf16.first else { continue }
            var chars = [UniChar(firstUTF16)]

            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                event.flags = []  // Explicitly clear any flags
                event.post(tap: .cghidEventTap)
            }

            usleep(Config.keyPressDuration)

            if let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                event.flags = []
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
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            NSLog("[Macro] openURL blocked non-http(s) scheme: %@", urlString)
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

/// Returns additional flags needed for special keys (arrow keys, function keys, etc.)
/// Delegates to KeyCodeMapping.specialKeyFlags for centralized, testable logic.
private func specialKeyFlags(for keyCode: CGKeyCode) -> CGEventFlags {
    KeyCodeMapping.specialKeyFlags(for: keyCode)
}
