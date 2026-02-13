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

        let mouseLocation = NSEvent.mouseLocation
        let panelSize = panel.frame.size

        // Center horizontally above cursor
        let x = mouseLocation.x - panelSize.width / 2
        let y = mouseLocation.y + cursorOffset

        panel.setFrameOrigin(NSPoint(x: x, y: y))
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

            // Held indicator
            if isHeld {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
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
        }
    }
}
