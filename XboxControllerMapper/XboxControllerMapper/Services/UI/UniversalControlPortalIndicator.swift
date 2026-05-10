import SwiftUI
import AppKit
import CoreGraphics

@MainActor
final class UniversalControlPortalIndicator {
    static let shared = UniversalControlPortalIndicator()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<EdgePortalView>?
    private var hideTimer: Timer?

    private let pulseDuration: TimeInterval = 0.55
    private let fadeDuration: TimeInterval = 0.18

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

    func clearRemoteReturnHint() {
        hideTimer?.invalidate()
        hideTimer = nil
        hide()
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

    private func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
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
