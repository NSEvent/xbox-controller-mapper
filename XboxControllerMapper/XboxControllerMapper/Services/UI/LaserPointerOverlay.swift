import SwiftUI
import AppKit

/// Displays a laser pointer dot centered on the cursor position
@MainActor
class LaserPointerOverlay {
    static let shared = LaserPointerOverlay()

    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fallbackTimer: DispatchSourceTimer?
    private(set) var isShowing = false

    private let dotSize: CGFloat = 50

    /// Base position for delta-based tracking during Accessibility Zoom
    private var basePosition: NSPoint?
    /// Whether we're currently using delta-based positioning (zoom active + moving)
    private var usingDeltaPositioning: Bool = false

    private init() {}

    func show() {
        guard !isShowing else { return }
        isShowing = true

        if panel == nil {
            createPanel()
        }

        // Reset delta-based positioning state
        basePosition = nil
        usingDeltaPositioning = false
        InputSimulator.resetMovementDelta()

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        updatePosition()

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel?.animator().alphaValue = 1
        }

        startTracking()
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false

        // Reset delta-based positioning state
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

    func toggle() {
        if isShowing {
            hide()
        } else {
            show()
        }
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: dotSize, height: dotSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false

        let hostingView = NSHostingView(rootView: LaserDotView(size: dotSize))
        hostingView.frame = NSRect(x: 0, y: 0, width: dotSize, height: dotSize)
        panel.contentView = hostingView

        self.panel = panel
    }

    private func startTracking() {
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

        // React immediately to every mouse movement event (global = other apps' events)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            // Callback runs on main thread; use assumeIsolated to avoid Task scheduling overhead
            MainActor.assumeIsolated {
                self?.updatePosition()
            }
        }

        // React immediately to mouse events going to our own app
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            MainActor.assumeIsolated {
                self?.updatePosition()
            }
            return event
        }

        // Fallback timer at 120Hz for Accessibility Zoom delta positioning
        // and edge cases where events may be coalesced
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.updatePosition()
            }
        }
        timer.resume()
        fallbackTimer = timer
    }

    private func stopTracking() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        fallbackTimer?.cancel()
        fallbackTimer = nil
    }

    private func updatePosition() {
        guard let panel = panel else { return }

        let offset = dotSize / 2
        let isZoomActive = UAZoomEnabled()
        let isMoving = InputSimulator.isCursorBeingMoved()

        if isZoomActive && isMoving {
            let delta = InputSimulator.consumeMovementDelta()

            if !usingDeltaPositioning {
                let mouseLocation = NSEvent.mouseLocation
                basePosition = NSPoint(x: mouseLocation.x - offset, y: mouseLocation.y - offset)
                usingDeltaPositioning = true
            }

            if var base = basePosition {
                let zoomLevel = max(1.0, InputSimulator.getZoomLevel())
                base.x += delta.x / zoomLevel
                base.y -= delta.y / zoomLevel
                basePosition = base
                panel.setFrameOrigin(base)
            }
        } else {
            if usingDeltaPositioning {
                usingDeltaPositioning = false
                InputSimulator.resetMovementDelta()
            }

            let mouseLocation = NSEvent.mouseLocation
            let position = NSPoint(x: mouseLocation.x - offset, y: mouseLocation.y - offset)
            basePosition = position
            panel.setFrameOrigin(position)
        }
    }
}

/// SwiftUI view that draws a laser pointer dot with a white-hot center and red glow
private struct LaserDotView: View {
    let size: CGFloat

    private let coreSize: CGFloat = 16

    var body: some View {
        ZStack {
            // Outer red glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.red.opacity(0.8),
                            Color.red.opacity(0.4),
                            Color.red.opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: coreSize / 2,
                        endRadius: size / 2
                    )
                )
                .frame(width: size, height: size)

            // White-hot center core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color.white.opacity(0.9),
                            Color(red: 1.0, green: 0.3, blue: 0.3).opacity(0.8),
                            Color.red.opacity(0.6)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: coreSize / 2
                    )
                )
                .frame(width: coreSize, height: coreSize)
        }
        .frame(width: size, height: size)
    }
}
