import SwiftUI
import AppKit

/// Displays a subtle ring around the cursor when focus mode is active
@MainActor
class FocusModeIndicator {
    static let shared = FocusModeIndicator()

    private var panel: NSPanel?
    private var trackingTimer: Timer?
    private var isVisible = false

    // Ring appearance settings
    private let ringSize: CGFloat = 28
    private let ringStrokeWidth: CGFloat = 2
    private let ringColor = NSColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.6)  // Soft blue

    private init() {}

    func show() {
        guard !isVisible else { return }
        isVisible = true

        if panel == nil {
            createPanel()
        }

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        updatePosition()

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel?.animator().alphaValue = 1
        }

        // Start tracking cursor position
        startTracking()
    }

    func hide() {
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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: ringSize, height: ringSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver  // Above everything including cursor
        panel.hasShadow = false
        panel.ignoresMouseEvents = true  // Click through
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        // Create the ring view
        let ringView = FocusRingView(frame: NSRect(x: 0, y: 0, width: ringSize, height: ringSize))
        ringView.ringColor = ringColor
        ringView.strokeWidth = ringStrokeWidth
        panel.contentView = ringView

        self.panel = panel
    }

    private func startTracking() {
        // Update position at 60fps for smooth tracking
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
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
        let offset = ringSize / 2

        // Center the ring on the cursor
        let x = mouseLocation.x - offset
        let y = mouseLocation.y - offset

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Custom view that draws the focus ring
private class FocusRingView: NSView {
    var ringColor: NSColor = .systemBlue
    var strokeWidth: CGFloat = 2

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let inset = strokeWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)

        context.setStrokeColor(ringColor.cgColor)
        context.setLineWidth(strokeWidth)
        context.strokeEllipse(in: rect)
    }
}
