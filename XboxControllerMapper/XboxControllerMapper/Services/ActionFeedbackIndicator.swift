import SwiftUI
import AppKit

/// Displays action feedback above the cursor when controller buttons are pressed
@MainActor
class ActionFeedbackIndicator {
    static let shared = ActionFeedbackIndicator()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<ActionFeedbackView>?
    private var hideTimer: Timer?
    private var trackingTimer: Timer?
    private var isVisible = false

    /// How long the feedback stays visible
    private let displayDuration: TimeInterval = 1.2
    /// Offset above the cursor
    private let cursorOffset: CGFloat = 30

    private init() {}

    /// Show action feedback above the cursor
    func show(action: String, type: InputEventType) {
        // Cancel any pending hide
        hideTimer?.invalidate()

        if panel == nil {
            createPanel()
        }

        // Update the content
        hostingView?.rootView = ActionFeedbackView(action: action, type: type)

        // Size to fit content
        if let hostingView = hostingView {
            let size = hostingView.fittingSize
            panel?.setContentSize(size)
        }

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

        // Schedule hide
        hideTimer = Timer.scheduledTimer(withTimeInterval: displayDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    private func hide() {
        guard isVisible else { return }
        isVisible = false
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 30)

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
private struct ActionFeedbackView: View {
    let action: String
    let type: InputEventType

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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
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
