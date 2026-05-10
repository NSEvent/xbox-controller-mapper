import SwiftUI
import AppKit
import CoreGraphics

@MainActor
final class UniversalControlPortalIndicator {
    static let shared = UniversalControlPortalIndicator()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<EdgePortalView>?
    private var hideTimer: Timer?
    private var cursorPanel: NSPanel?
    private var cursorHostingView: NSHostingView<CursorTeleportView>?
    private var cursorHideTimer: Timer?
    private var cursorTrackingTimer: Timer?

    private let pulseDuration: TimeInterval = 0.55
    private let fadeDuration: TimeInterval = 0.18
    private let cursorSize: CGFloat = 46

    private init() {}

    func flash(edge: UniversalControlMouseRelay.HandoffEdge, displayID: CGDirectDisplayID? = nil) {
        let screen = screen(displayID: displayID) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        show(
            on: screen,
            pulseEdge: edge,
            persistentEdge: nil,
            pulseActive: true
        )

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: pulseDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }
    }

    func showRemoteEntry(
        entryEdge: UniversalControlMouseRelay.HandoffEdge,
        returnEdge: UniversalControlMouseRelay.HandoffEdge
    ) {
        let screen = screen(containing: NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        show(
            on: screen,
            pulseEdge: entryEdge,
            persistentEdge: returnEdge,
            pulseActive: true
        )
        flashActiveCursor()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: pulseDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.show(
                    on: screen,
                    pulseEdge: nil,
                    persistentEdge: returnEdge,
                    pulseActive: false
                )
            }
        }
    }

    func showInactiveCursor(at cgPoint: CGPoint, displayID: CGDirectDisplayID) {
        guard let screen = screen(displayID: displayID) ?? NSScreen.main else { return }
        let displayBounds = CGDisplayBounds(displayID)
        let point = NSPoint(
            x: screen.frame.minX + cgPoint.x - displayBounds.minX,
            y: screen.frame.maxY - (cgPoint.y - displayBounds.minY)
        )
        showCursor(at: point, state: .inactive, persistent: true)
    }

    func flashActiveCursor() {
        showCursor(at: NSEvent.mouseLocation, state: .active, persistent: false)
        startCursorTracking()
        cursorHideTimer?.invalidate()
        cursorHideTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hideCursor()
            }
        }
    }

    func clearRemoteReturnHint() {
        hideTimer?.invalidate()
        hideTimer = nil
        hide()
        clearCursorState()
    }

    func clearCursorState() {
        cursorHideTimer?.invalidate()
        cursorHideTimer = nil
        hideCursor()
    }

    private func show(
        on screen: NSScreen,
        pulseEdge: UniversalControlMouseRelay.HandoffEdge?,
        persistentEdge: UniversalControlMouseRelay.HandoffEdge?,
        pulseActive: Bool
    ) {
        ensurePanel(on: screen)
        hostingView?.rootView = EdgePortalView(
            pulseEdge: pulseEdge,
            persistentEdge: persistentEdge,
            pulseActive: pulseActive
        )
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
    }

    private func showCursor(at point: NSPoint, state: CursorTeleportState, persistent: Bool) {
        ensureCursorPanel()
        cursorHostingView?.rootView = CursorTeleportView(state: state)
        cursorPanel?.alphaValue = 1
        setCursorPanelCenter(point)
        cursorPanel?.orderFrontRegardless()

        if persistent {
            cursorHideTimer?.invalidate()
            cursorHideTimer = nil
            stopCursorTracking()
        }
    }

    private func setCursorPanelCenter(_ point: NSPoint) {
        cursorPanel?.setFrameOrigin(NSPoint(
            x: point.x - cursorSize / 2,
            y: point.y - cursorSize / 2
        ))
    }

    private func startCursorTracking() {
        cursorTrackingTimer?.invalidate()
        cursorTrackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.setCursorPanelCenter(NSEvent.mouseLocation)
            }
        }
        if let cursorTrackingTimer {
            RunLoop.main.add(cursorTrackingTimer, forMode: .common)
        }
    }

    private func stopCursorTracking() {
        cursorTrackingTimer?.invalidate()
        cursorTrackingTimer = nil
    }

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    private func hideCursor() {
        guard let cursorPanel else { return }
        stopCursorTracking()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            cursorPanel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.cursorPanel?.orderOut(nil)
        }
    }

    private func ensurePanel(on screen: NSScreen) {
        if let panel, panel.frame.equalTo(screen.frame) {
            return
        }

        let rootView = EdgePortalView(pulseEdge: nil, persistentEdge: nil, pulseActive: false)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(origin: .zero, size: screen.frame.size)

        let panel = NSPanel(
            contentRect: screen.frame,
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
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
    }

    private func ensureCursorPanel() {
        if cursorPanel != nil {
            return
        }

        let rootView = CursorTeleportView(state: .inactive)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: cursorSize, height: cursorSize)

        let panel = NSPanel(
            contentRect: hostingView.frame,
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
        panel.contentView = hostingView

        self.cursorPanel = panel
        self.cursorHostingView = hostingView
    }

    private func screen(displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == displayID
        }
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

private struct EdgePortalView: View {
    let pulseEdge: UniversalControlMouseRelay.HandoffEdge?
    let persistentEdge: UniversalControlMouseRelay.HandoffEdge?
    let pulseActive: Bool

    private let portalColor = Color(red: 0.18, green: 0.88, blue: 1.0)

    var body: some View {
        ZStack {
            if let persistentEdge {
                edgeLight(edge: persistentEdge, width: 22, intensity: 0.34)
            }
            if let pulseEdge, pulseActive {
                edgeLight(edge: pulseEdge, width: 96, intensity: 1.0)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    @ViewBuilder
    private func edgeLight(
        edge: UniversalControlMouseRelay.HandoffEdge,
        width: CGFloat,
        intensity: Double
    ) -> some View {
        switch edge {
        case .left:
            HStack(spacing: 0) {
                portalStrip(edge: edge, width: width, intensity: intensity)
                Spacer(minLength: 0)
            }
        case .right:
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                portalStrip(edge: edge, width: width, intensity: intensity)
            }
        case .top:
            VStack(spacing: 0) {
                portalStrip(edge: edge, width: width, intensity: intensity)
                Spacer(minLength: 0)
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                portalStrip(edge: edge, width: width, intensity: intensity)
            }
        }
    }

    private func portalStrip(
        edge: UniversalControlMouseRelay.HandoffEdge,
        width: CGFloat,
        intensity: Double
    ) -> some View {
        let isVertical = edge == .left || edge == .right
        return ZStack {
            portalGradient(edge: edge)
            edgeCore(edge: edge, isVertical: isVertical)
        }
        .frame(
            width: isVertical ? width : nil,
            height: isVertical ? nil : width
        )
        .opacity(intensity)
        .shadow(color: portalColor.opacity(0.65 * intensity), radius: width * 0.22)
        .allowsHitTesting(false)
    }

    private func portalGradient(edge: UniversalControlMouseRelay.HandoffEdge) -> some View {
        LinearGradient(
            colors: [
                portalColor.opacity(0.86),
                portalColor.opacity(0.28),
                portalColor.opacity(0.08),
                .clear
            ],
            startPoint: gradientStart(for: edge),
            endPoint: gradientEnd(for: edge)
        )
    }

    private func edgeCore(edge: UniversalControlMouseRelay.HandoffEdge, isVertical: Bool) -> some View {
        Rectangle()
            .fill(portalColor.opacity(0.95))
            .frame(width: isVertical ? 3 : nil, height: isVertical ? nil : 3)
            .frame(
                maxWidth: isVertical ? .infinity : nil,
                maxHeight: isVertical ? nil : .infinity,
                alignment: coreAlignment(for: edge)
            )
    }

    private func gradientStart(for edge: UniversalControlMouseRelay.HandoffEdge) -> UnitPoint {
        switch edge {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private func gradientEnd(for edge: UniversalControlMouseRelay.HandoffEdge) -> UnitPoint {
        switch edge {
        case .left: return .trailing
        case .right: return .leading
        case .top: return .bottom
        case .bottom: return .top
        }
    }

    private func coreAlignment(for edge: UniversalControlMouseRelay.HandoffEdge) -> Alignment {
        switch edge {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

private enum CursorTeleportState: Equatable {
    case active
    case inactive

    var color: Color {
        Color(red: 0.18, green: 0.88, blue: 1.0)
    }

    var opacity: Double {
        switch self {
        case .active: return 0.92
        case .inactive: return 0.72
        }
    }
}

private struct CursorTeleportView: View {
    let state: CursorTeleportState

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            state.color.opacity(state == .active ? 0.44 : 0.34),
                            state.color.opacity(state == .active ? 0.08 : 0.16),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 23
                    )
                )
                .frame(width: 46, height: 46)

            if state == .inactive {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.85),
                                state.color.opacity(0.95),
                                state.color.opacity(0.20),
                                state.color.opacity(0.95),
                                .white.opacity(0.85)
                            ],
                            center: .center
                        ),
                        lineWidth: 3.5
                    )
                    .frame(width: 31, height: 31)
                    .shadow(color: state.color.opacity(0.82), radius: 7)

                Circle()
                    .trim(from: 0.08, to: 0.34)
                    .stroke(.white.opacity(0.72), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(-18))

                Circle()
                    .trim(from: 0.58, to: 0.84)
                    .stroke(state.color.opacity(0.72), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(24))
            } else {
                Circle()
                    .stroke(state.color.opacity(state.opacity), lineWidth: 2.5)
                    .frame(width: 30, height: 30)
                    .shadow(color: state.color.opacity(state.opacity), radius: 6)

                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 46, height: 46)
        .allowsHitTesting(false)
    }
}
