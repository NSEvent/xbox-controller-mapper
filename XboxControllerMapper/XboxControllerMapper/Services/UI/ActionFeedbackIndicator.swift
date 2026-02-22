import SwiftUI
import AppKit

/// Displays action feedback above the cursor when controller buttons are pressed
@MainActor
class ActionFeedbackIndicator {
    static let shared = ActionFeedbackIndicator()

    /// Whether action feedback is enabled (stored in UserDefaults, defaults to true)
    static var isEnabled: Bool {
        get {
            // Default to true if key hasn't been set
            if UserDefaults.standard.object(forKey: "actionFeedbackEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "actionFeedbackEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "actionFeedbackEnabled") }
    }

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ActionFeedbackView>?
    private var hideTimer: Timer?
    private var trackingTimer: Timer?
    private var isVisible = false
    private var showTime: Date?  // When the indicator was shown

    /// Currently held actions (maps action string to input type for display)
    private var heldActions: [String: InputEventType] = [:]

    /// How long the feedback stays visible (for non-held actions)
    private let displayDuration: TimeInterval = 1.2
    /// Minimum display time even for quick taps on held actions
    private let minimumDisplayDuration: TimeInterval = 0.8
    /// Offset above the cursor
    private let cursorOffset: CGFloat = 30

    /// Base position for delta-based tracking during Accessibility Zoom
    /// When zoom is active, we apply movement deltas to this base position
    /// to avoid coordinate inconsistencies from NSEvent.mouseLocation
    private var basePosition: NSPoint?
    /// Whether we're currently using delta-based positioning (zoom active + moving)
    private var usingDeltaPositioning: Bool = false

    private init() {}

    /// Show action feedback above the cursor
    /// - Parameters:
    ///   - action: The action text to display
    ///   - type: The type of input event
    ///   - isHeld: If true, the indicator stays until dismissHeld() is called
    func show(action: String, type: InputEventType, isHeld: Bool = false) {
        // Check if action feedback is enabled
        guard Self.isEnabled else { return }

        // Cancel any pending hide
        hideTimer?.invalidate()

        if panel == nil {
            createPanel()
        }

        // Track held actions
        if isHeld {
            heldActions[action] = type
        }

        // Determine what to display
        let displayAction: String
        let displayIsHeld: Bool

        if !heldActions.isEmpty {
            // Combine all held actions (sorted for consistent ordering)
            displayAction = heldActions.keys.sorted().joined(separator: " + ")
            displayIsHeld = true
        } else {
            displayAction = action
            displayIsHeld = isHeld
        }

        // Update the content
        hostingView?.rootView = ActionFeedbackView(action: displayAction, type: type, isHeld: displayIsHeld)

        // Size to fit content
        if let hostingView = hostingView {
            let size = hostingView.fittingSize
            panel?.setContentSize(size)
        }

        self.showTime = Date()

        if !isVisible {
            isVisible = true
            basePosition = nil  // Reset position tracking
            usingDeltaPositioning = false
            InputSimulator.resetMovementDelta()  // Clear any accumulated delta
            panel?.alphaValue = 0
            panel?.orderFrontRegardless()
            startTracking()

            // Fade in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                panel?.animator().alphaValue = 1
            }
        }

        updatePosition()

        // Only schedule auto-hide for non-held actions when no held actions are active
        if !isHeld && heldActions.isEmpty {
            hideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.hide()
                }
            }
        }
    }

    /// Dismiss a specific held action (call when button is released)
    /// - Parameter action: The action string to dismiss. If nil, dismisses all held actions.
    func dismissHeld(action: String? = nil) {
        if let action = action {
            // Remove specific held action
            heldActions.removeValue(forKey: action)

            // If there are still other held actions, update the display
            if !heldActions.isEmpty {
                let displayAction = heldActions.keys.sorted().joined(separator: " + ")
                let type = heldActions.values.first ?? .singlePress
                hostingView?.rootView = ActionFeedbackView(action: displayAction, type: type, isHeld: true)

                // Resize panel to fit new content
                if let hostingView = hostingView {
                    let size = hostingView.fittingSize
                    panel?.setContentSize(size)
                }
                return
            }
        } else {
            // Clear all held actions
            heldActions.removeAll()
        }

        // No more held actions - hide the indicator
        guard isVisible else { return }

        // Ensure minimum display time for quick taps
        if let showTime = showTime {
            let elapsed = Date().timeIntervalSince(showTime)
            if elapsed < minimumDisplayDuration {
                // Schedule hide after remaining time
                let remaining = minimumDisplayDuration - elapsed
                hideTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.hide()
                    }
                }
                return
            }
        }

        hide()
    }

    private func hide() {
        guard isVisible else { return }
        isVisible = false
        heldActions.removeAll()
        basePosition = nil
        usingDeltaPositioning = false
        stopTracking()

        // Fade out
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel?.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        })
    }

    private func createPanel() {
        let initialView = ActionFeedbackView(action: "", type: .singlePress)
        let hostingView = NSHostingView(rootView: initialView)
        // Use fittingSize to get intrinsic content size (no fixed width constraint)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver  // Above cursor
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
    }

    private func startTracking() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePosition()
            }
        }
        RunLoop.main.add(trackingTimer!, forMode: .common)
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func updatePosition() {
        guard let panel = panel else { return }

        let panelSize = panel.frame.size
        let isZoomActive = UAZoomEnabled()
        let isMoving = InputSimulator.isCursorBeingMoved()

        // Strategy for Accessibility Zoom:
        // - When movement starts: capture base position from NSEvent.mouseLocation
        // - During movement: apply deltas to base position (avoids unreliable absolute coords)
        // - When movement stops: resync to NSEvent.mouseLocation

        if isZoomActive && isMoving {
            // Cursor is being moved with zoom active - use delta-based positioning
            let delta = InputSimulator.consumeMovementDelta()

            if !usingDeltaPositioning {
                // Just started moving - establish base position
                let mouseLocation = NSEvent.mouseLocation
                let baseX = mouseLocation.x - panelSize.width / 2
                let baseY = mouseLocation.y + cursorOffset
                basePosition = NSPoint(x: baseX, y: baseY)
                usingDeltaPositioning = true
            }

            if var base = basePosition {
                // Apply delta scaled inversely by zoom level
                // The hint position is in screen coords, which get magnified by zoom.
                // To make the hint follow the visual cursor, we divide by zoom level.
                // Delta Y is in CG coords where +Y is down, but NS coords have +Y up, so we subtract
                let zoomLevel = max(1.0, InputSimulator.getZoomLevel())
                base.x += delta.x / zoomLevel
                base.y -= delta.y / zoomLevel
                basePosition = base
                panel.setFrameOrigin(base)
            }
        } else {
            // Not moving or zoom not active - use absolute positioning
            if usingDeltaPositioning {
                // Just stopped moving - resync
                usingDeltaPositioning = false
                InputSimulator.resetMovementDelta()
            }

            let mouseLocation = NSEvent.mouseLocation
            let x = mouseLocation.x - panelSize.width / 2
            let y = mouseLocation.y + cursorOffset
            let position = NSPoint(x: x, y: y)
            basePosition = position
            panel.setFrameOrigin(position)
        }
    }
}

/// SwiftUI view that displays the action in a chip style matching the app's aesthetic
/// Internal visibility for testing
struct ActionFeedbackView: View {
    let action: String
    let type: InputEventType
    var isHeld: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            // Hold badge (shown first for held actions)
            if isHeld {
                Text("▼")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.purple)
                    .cornerRadius(3)
            }

            // Type indicator badge
            if let badge = typeBadge {
                Text(badge.icon)
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(badge.color)
                    .cornerRadius(3)
            }

            // Action text
            Text(action)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHeld ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.15), lineWidth: isHeld ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        .fixedSize()  // Prevent truncation - always size to fit content
    }

    private var typeBadge: (icon: String, color: Color)? {
        switch type {
        case .singlePress:
            return nil  // No badge for single press
        case .doubleTap:
            return ("2×", .cyan)
        case .longPress:
            return ("⏱", .orange)
        case .chord:
            return ("⌘", .blue)
        case .sequence:
            return ("⇢", .cyan)
        case .webhookSuccess:
            return ("✓", .green)
        case .webhookFailure:
            return ("✗", .red)
        case .gesture:
            return ("↻", .teal)
        }
    }
}
