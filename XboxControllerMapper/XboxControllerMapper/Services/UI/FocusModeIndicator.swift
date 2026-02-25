import SwiftUI
import AppKit

/// Displays a subtle jewel-style ring around the cursor when focus mode is active
@MainActor
class FocusModeIndicator {
    static let shared = FocusModeIndicator()

    /// Whether focus cursor highlight is enabled (stored in UserDefaults, defaults to true)
    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "focusCursorHighlightEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "focusCursorHighlightEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "focusCursorHighlightEnabled") }
    }

    private var panel: NSPanel?
    private var trackingTimer: Timer?
    private var isVisible = false
    /// Last confirmed physical cursor position during zoom (NS coords)
    private var lastPhysicalPosition: NSPoint?

    // Ring appearance settings - matches the app's "jewel" aesthetic
    private let ringSize: CGFloat = 32
    private let ringStrokeWidth: CGFloat = 3

    private init() {}

    func show() {
        guard Self.isEnabled, !isVisible else { return }
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
        panel.level = .screenSaver
        panel.hasShadow = false
        panel.ignoresMouseEvents = true  // Click through
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        // Create the jewel ring view using SwiftUI for the gradient effects
        let hostingView = NSHostingView(rootView: FocusRingSwiftUIView(size: ringSize, strokeWidth: ringStrokeWidth))
        hostingView.frame = NSRect(x: 0, y: 0, width: ringSize, height: ringSize)
        panel.contentView = hostingView

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

        let offset = ringSize / 2
        let zoomLevel = InputSimulator.getZoomLevel()
        let isZoomed = InputSimulator.isZoomCurrentlyActive() && zoomLevel > 1.0
        let tracked = InputSimulator.getLastTrackedPosition()
        let mouseLocation = NSEvent.mouseLocation

        if isZoomed, let tracked = tracked {
            // During Accessibility Zoom, NSEvent.mouseLocation oscillates between
            // virtual (absolute) and physical (visual) cursor positions on alternating
            // reads. Filter out virtual readings by comparing to our tracked position.
            let screenHeight = NSScreen.screens.first?.frame.height ?? 1329
            let virtualNS = NSPoint(x: tracked.x, y: screenHeight - tracked.y)

            let tolerance: CGFloat = 10
            let isVirtualReading = abs(mouseLocation.x - virtualNS.x) < tolerance
                                && abs(mouseLocation.y - virtualNS.y) < tolerance

            let cursorPos: NSPoint
            if isVirtualReading {
                guard let last = lastPhysicalPosition else { return }
                cursorPos = last
            } else {
                lastPhysicalPosition = mouseLocation
                cursorPos = mouseLocation
            }

            panel.setFrameOrigin(NSPoint(x: cursorPos.x - offset, y: cursorPos.y - offset))
        } else {
            lastPhysicalPosition = nil
            panel.setFrameOrigin(NSPoint(x: mouseLocation.x - offset, y: mouseLocation.y - offset))
        }
    }
}

/// SwiftUI view that draws the jewel-style focus ring matching the app's aesthetic
private struct FocusRingSwiftUIView: View {
    let size: CGFloat
    let strokeWidth: CGFloat

    // Use a purple/accent color that matches the focus mode theme
    private let baseColor = Color(red: 0.6, green: 0.4, blue: 0.9)  // Purple focus color

    var body: some View {
        ZStack {
            // 1. Base gradient ring with shadow
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [baseColor, baseColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: strokeWidth
                )
                .shadow(color: baseColor.opacity(0.5), radius: 4, x: 0, y: 0)

            // 2. Inner glow
            Circle()
                .strokeBorder(
                    RadialGradient(
                        colors: [baseColor.opacity(0.3), .clear],
                        center: .center,
                        startRadius: size/2 - strokeWidth - 2,
                        endRadius: size/2 - strokeWidth + 4
                    ),
                    lineWidth: strokeWidth + 4
                )

            // 3. Glassy highlight on top edge
            Circle()
                .trim(from: 0.6, to: 0.9)  // Top arc only
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 1.5
                )
                .padding(strokeWidth / 2)

            // 4. Subtle outer glow
            Circle()
                .stroke(baseColor.opacity(0.2), lineWidth: 1)
                .padding(-2)
        }
        .frame(width: size, height: size)
    }
}
