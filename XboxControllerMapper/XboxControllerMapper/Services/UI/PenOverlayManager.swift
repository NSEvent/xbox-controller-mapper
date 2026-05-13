import SwiftUI
import AppKit
import Combine

private enum PenStrokeMode {
    case fade
    case permanent

    var opposite: PenStrokeMode {
        switch self {
        case .fade: return .permanent
        case .permanent: return .fade
        }
    }

    var label: String {
        switch self {
        case .fade: return "Fade 3s"
        case .permanent: return "Keep"
        }
    }
}

private struct PenPaletteColor {
    let name: String
    let color: Color
}

private struct PenStroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    let color: Color
    let lineWidth: CGFloat
    let mode: PenStrokeMode
    let createdAt: TimeInterval
    var endedAt: TimeInterval?
}

@MainActor
final class PenOverlayManager: ObservableObject {
    static let shared = PenOverlayManager()

    @Published fileprivate private(set) var strokes: [PenStroke] = []
    @Published fileprivate private(set) var currentStroke: PenStroke?
    @Published fileprivate private(set) var cursorPosition: CGPoint = .zero
    @Published fileprivate private(set) var now: TimeInterval = ProcessInfo.processInfo.systemUptime
    @Published fileprivate private(set) var hudText = "Pen - Fade 3s"
    @Published fileprivate private(set) var hudVisible = false
    @Published fileprivate private(set) var controlsVisible = false
    @Published fileprivate private(set) var activeVisibleRect: CGRect = .zero
    @Published fileprivate private(set) var isShowing = false
    @Published fileprivate private(set) var cursorIsKeepMode = false

    private static let palette: [PenPaletteColor] = [
        PenPaletteColor(name: "Blue", color: Color(red: 0.14, green: 0.64, blue: 1.0)),
        PenPaletteColor(name: "Yellow", color: Color(red: 1.0, green: 0.86, blue: 0.18)),
        PenPaletteColor(name: "Pink", color: Color(red: 1.0, green: 0.22, blue: 0.58)),
        PenPaletteColor(name: "Green", color: Color(red: 0.18, green: 0.92, blue: 0.54)),
        PenPaletteColor(name: "White", color: .white)
    ]

    private let fadeDuration: TimeInterval = 3.0
    private let minimumPointDistance: CGFloat = 0.65
    private let maximumPointSpacing: CGFloat = 3.5
    private let cursorPublishDistance: CGFloat = 0.2
    private nonisolated(unsafe) let stateLock = NSLock()
    private nonisolated(unsafe) var threadSafeVisible = false
    private var panel: NSPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fallbackTimer: DispatchSourceTimer?
    private var hudHideWorkItem: DispatchWorkItem?
    private var controlsHideWorkItem: DispatchWorkItem?
    private var clearHoldWorkItem: DispatchWorkItem?
    private var currentMode: PenStrokeMode = .fade
    private var colorIndex = 0
    private var lineWidth: CGFloat = 7
    private var panelFrame: CGRect = .zero
    private var aButtonDown = false
    private var aPressUsedAsModifier = false
    private var clearHoldDidFire = false

    nonisolated var threadSafeIsVisible: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return threadSafeVisible
    }

    nonisolated static func isControllerControl(_ button: ControllerButton) -> Bool {
        switch button {
        case .a, .b, .x, .y,
             .leftBumper, .rightBumper,
             .rightTrigger, .menu,
             .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
            return true
        default:
            return false
        }
    }

    private init() {}

    func show() {
        guard !isShowing else { return }
        isShowing = true
        updateThreadSafeVisible(true)

        LaserPointerOverlay.shared.hide()
        CommandWheelManager.shared.hide()
        DirectoryNavigatorManager.shared.hide()
        OnScreenKeyboardManager.shared.hide()

        ensurePanel()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        updateCursorPosition()
        updateCursorMode()
        showHUD("Pen - \(currentMode.label)")
        showControls()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel?.animator().alphaValue = 1
        }

        startTracking()
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        updateThreadSafeVisible(false)
        endStroke()
        stopTracking()
        strokes.removeAll()
        currentStroke = nil
        aButtonDown = false
        aPressUsedAsModifier = false
        cancelClearHold()
        updateCursorMode()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
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

    @discardableResult
    func handleButtonPress(_ button: ControllerButton) -> Bool {
        guard isShowing else { return false }
        switch button {
        case .a:
            aButtonDown = true
            aPressUsedAsModifier = currentStroke != nil
            updateCursorMode()
        case .rightTrigger:
            if aButtonDown {
                aPressUsedAsModifier = true
            }
            beginStroke(mode: aButtonDown ? currentMode.opposite : currentMode)
        case .b:
            undoLastStroke()
        case .x:
            scheduleClearHold()
        case .y:
            cycleColor(by: 1)
        case .leftBumper:
            adjustLineWidth(by: -1)
        case .rightBumper:
            adjustLineWidth(by: 1)
        case .dpadLeft:
            adjustLineWidth(by: -1)
        case .dpadRight:
            adjustLineWidth(by: 1)
        case .dpadUp:
            cycleColor(by: 1)
        case .dpadDown:
            cycleColor(by: -1)
        case .menu:
            hide()
        default:
            return false
        }
        return true
    }

    @discardableResult
    func handleButtonRelease(_ button: ControllerButton) -> Bool {
        switch button {
        case .a:
            if aButtonDown, !aPressUsedAsModifier {
                toggleMode()
            }
            aButtonDown = false
            aPressUsedAsModifier = false
            updateCursorMode()
        case .rightTrigger:
            endStroke()
        case .x:
            cancelClearHold()
        default:
            return false
        }
        return true
    }

    private func beginStroke(mode: PenStrokeMode? = nil) {
        guard isShowing, currentStroke == nil else { return }
        updateCursorPosition()
        let uptime = ProcessInfo.processInfo.systemUptime
        let strokeMode = mode ?? currentMode
        currentStroke = PenStroke(
            points: [cursorPosition],
            color: Self.palette[colorIndex].color,
            lineWidth: lineWidth,
            mode: strokeMode,
            createdAt: uptime,
            endedAt: nil
        )
        updateCursorMode()
        if strokeMode != currentMode {
            showHUD(strokeMode.label)
        }
    }

    func endStroke() {
        guard var stroke = currentStroke else { return }
        stroke.endedAt = ProcessInfo.processInfo.systemUptime
        strokes.append(stroke)
        currentStroke = nil
        pruneExpiredStrokes()
        updateCursorMode()
    }

    private func ensurePanel() {
        let frame = overlayFrame()
        panelFrame = frame

        if panel == nil {
            let panel = NSPanel(
                contentRect: frame,
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
            panel.contentView = NSHostingView(rootView: PenOverlayView(manager: self))
            self.panel = panel
        }

        panel?.setFrame(frame, display: true)
    }

    private func startTracking() {
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCursorPosition()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            MainActor.assumeIsolated {
                self?.updateCursorPosition()
            }
            return event
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.tick()
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
        hudHideWorkItem?.cancel()
        hudHideWorkItem = nil
        controlsHideWorkItem?.cancel()
        controlsHideWorkItem = nil
        cancelClearHold()
    }

    private func tick() {
        now = ProcessInfo.processInfo.systemUptime
        let frame = overlayFrame()
        if frame != panelFrame {
            panelFrame = frame
            panel?.setFrame(frame, display: true)
        }
        updateCursorPosition()
        pruneExpiredStrokes()
    }

    private func updateCursorPosition() {
        let frame = panelFrame == .zero ? overlayFrame() : panelFrame
        let mouse = NSEvent.mouseLocation
        updateActiveVisibleRect(for: mouse, panelFrame: frame)
        let point = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        if hypot(cursorPosition.x - point.x, cursorPosition.y - point.y) >= cursorPublishDistance {
            cursorPosition = point
        }

        appendStrokePoint(point)
    }

    private func appendStrokePoint(_ point: CGPoint) {
        guard var stroke = currentStroke else { return }
        guard let last = stroke.points.last else {
            stroke.points.append(point)
            currentStroke = stroke
            return
        }

        let distance = hypot(last.x - point.x, last.y - point.y)
        guard distance >= minimumPointDistance else {
            return
        }

        if distance > maximumPointSpacing {
            let extraPointCount = min(24, Int(distance / maximumPointSpacing))
            for step in 1...extraPointCount {
                let progress = CGFloat(step) / CGFloat(extraPointCount + 1)
                stroke.points.append(CGPoint(
                    x: last.x + (point.x - last.x) * progress,
                    y: last.y + (point.y - last.y) * progress
                ))
            }
        }

        stroke.points.append(point)
        currentStroke = stroke
    }

    private func undoLastStroke() {
        if currentStroke != nil {
            currentStroke = nil
        } else if !strokes.isEmpty {
            strokes.removeLast()
        }
        showHUD("Undo")
    }

    private func clear() {
        strokes.removeAll()
        currentStroke = nil
        showHUD("Cleared")
        updateCursorMode()
    }

    private func toggleMode() {
        currentMode = currentMode == .fade ? .permanent : .fade
        showHUD(currentMode == .fade ? "Fade drawings" : "Keep drawings")
        updateCursorMode()
    }

    private func adjustLineWidth(by delta: CGFloat) {
        lineWidth = min(18, max(3, lineWidth + delta))
        showHUD("Width \(Int(lineWidth))")
    }

    private func cycleColor(by delta: Int) {
        let count = Self.palette.count
        colorIndex = (colorIndex + delta + count) % count
        showHUD(Self.palette[colorIndex].name)
    }

    private func scheduleClearHold() {
        clearHoldWorkItem?.cancel()
        clearHoldDidFire = false
        showHUD("Hold X to Clear")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.clearHoldDidFire = true
            self.clear()
        }
        clearHoldWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65, execute: workItem)
    }

    private func cancelClearHold() {
        clearHoldWorkItem?.cancel()
        clearHoldWorkItem = nil
        if clearHoldDidFire {
            clearHoldDidFire = false
        }
    }

    private func updateCursorMode() {
        let pendingMode = aButtonDown && currentStroke == nil ? currentMode.opposite : currentMode
        cursorIsKeepMode = (currentStroke?.mode ?? pendingMode) == .permanent
    }

    private func pruneExpiredStrokes() {
        strokes.removeAll { stroke in
            guard stroke.mode == .fade, let endedAt = stroke.endedAt else { return false }
            return now - endedAt >= fadeDuration
        }
    }

    private func showHUD(_ text: String) {
        hudHideWorkItem?.cancel()
        hudText = text
        hudVisible = true

        let workItem = DispatchWorkItem { [weak self] in
            self?.hudVisible = false
        }
        hudHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: workItem)
    }

    private func showControls() {
        controlsHideWorkItem?.cancel()
        controlsVisible = true
    }

    private func updateActiveVisibleRect(for mouse: CGPoint, panelFrame: CGRect) {
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            activeVisibleRect = CGRect(origin: .zero, size: panelFrame.size)
            return
        }

        let visible = screen.visibleFrame.insetBy(dx: 18, dy: 18)
        let rect = CGRect(
            x: visible.minX - panelFrame.minX,
            y: panelFrame.maxY - visible.maxY,
            width: visible.width,
            height: visible.height
        )
        if activeVisibleRect != rect {
            activeVisibleRect = rect
        }
    }

    private func overlayFrame() -> CGRect {
        let screens = NSScreen.screens.map(\.frame)
        return screens.reduce(CGRect.null) { $0.union($1) }
    }

    private func updateThreadSafeVisible(_ visible: Bool) {
        stateLock.lock()
        threadSafeVisible = visible
        stateLock.unlock()
    }

    fileprivate func opacity(for stroke: PenStroke) -> Double {
        guard stroke.mode == .fade, let endedAt = stroke.endedAt else { return 1 }
        let progress = min(1, max(0, (now - endedAt) / fadeDuration))
        return pow(1 - progress, 0.65)
    }
}

private struct PenOverlayView: View {
    @ObservedObject var manager: PenOverlayManager

    var body: some View {
        GeometryReader { geometry in
            ZStack {
            Canvas { context, _ in
                for stroke in manager.strokes {
                    draw(stroke, in: &context, opacity: manager.opacity(for: stroke))
                }
                if let stroke = manager.currentStroke {
                    draw(stroke, in: &context, opacity: 1)
                }
            }

            cursorMarker

                if manager.hudVisible {
                    statusPill
                        .position(x: safeRect(in: geometry).midX, y: safeRect(in: geometry).minY + 28)
                }

                if manager.controlsVisible {
                    controlsStrip
                        .position(x: safeRect(in: geometry).midX, y: safeRect(in: geometry).maxY - 34)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var statusPill: some View {
        Text(manager.hudText)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.5), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.24), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    private var controlsStrip: some View {
        HStack(spacing: 10) {
            hint([.rightTrigger], "Draw")
            hint([.a], "Mode")
            hint([.y], "Color")
            hint([.leftBumper, .rightBumper], "Width")
            hint([.b], "Undo")
            hint([.x], "Hold Clear")
            hint([.menu], "Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(Color(red: 0.14, green: 0.64, blue: 1.0).opacity(0.35), lineWidth: 1))
        .shadow(color: Color(red: 0.14, green: 0.64, blue: 1.0).opacity(0.22), radius: 18, y: 5)
    }

    private func hint(_ buttons: [ControllerButton], _ action: String) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: -2) {
                ForEach(buttons, id: \.self) { button in
                    ButtonIconView(button: button)
                        .scaleEffect(0.78)
                        .frame(width: iconFrameWidth(for: button), height: 22)
                }
            }
            Text(action)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private func iconFrameWidth(for button: ControllerButton) -> CGFloat {
        switch button.category {
        case .trigger:
            return 34
        case .bumper, .paddle:
            return 30
        case .touchpad:
            return 34
        case .face, .special, .thumbstick, .dpad:
            return 23
        }
    }

    private func safeRect(in geometry: GeometryProxy) -> CGRect {
        if manager.activeVisibleRect.width > 0, manager.activeVisibleRect.height > 0 {
            return manager.activeVisibleRect
        }
        return CGRect(origin: .zero, size: geometry.size).insetBy(dx: 18, dy: 82)
    }

    private var cursorMarker: some View {
        let accentColor = manager.cursorIsKeepMode
            ? Color(red: 1.0, green: 0.86, blue: 0.18)
            : Color(red: 0.14, green: 0.64, blue: 1.0)

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: 22, height: 22)
            Circle()
                .stroke(accentColor.opacity(0.9), lineWidth: 2)
                .frame(width: 30, height: 30)
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)

            if manager.cursorIsKeepMode {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 14, height: 14)
                    .background(accentColor, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                    .offset(x: 14, y: -14)
            }
        }
        .shadow(color: accentColor.opacity(0.7), radius: 10)
        .position(manager.cursorPosition)
    }

    private func draw(_ stroke: PenStroke, in context: inout GraphicsContext, opacity: Double) {
        guard let first = stroke.points.first else { return }
        let isKept = stroke.mode == .permanent

        if stroke.points.count == 1 {
            let radius = stroke.lineWidth / 2
            let rect = CGRect(x: first.x - radius, y: first.y - radius, width: stroke.lineWidth, height: stroke.lineWidth)
            if isKept {
                let outlineRadius = radius + 2
                let outlineRect = CGRect(
                    x: first.x - outlineRadius,
                    y: first.y - outlineRadius,
                    width: outlineRadius * 2,
                    height: outlineRadius * 2
                )
                context.fill(Path(ellipseIn: outlineRect), with: .color(.white.opacity(0.45 * opacity)))
            }
            context.fill(Path(ellipseIn: rect), with: .color(stroke.color.opacity(opacity)))
            return
        }

        let path = smoothedPath(for: stroke.points, startingAt: first)
        if isKept {
            context.stroke(
                path,
                with: .color(.white.opacity(0.36 * opacity)),
                style: StrokeStyle(lineWidth: stroke.lineWidth + 4, lineCap: .round, lineJoin: .round)
            )
        }
        context.stroke(
            path,
            with: .color(stroke.color.opacity(opacity)),
            style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func smoothedPath(for points: [CGPoint], startingAt first: CGPoint) -> Path {
        var path = Path()
        path.move(to: first)

        guard points.count > 2 else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            return path
        }

        for index in 1..<points.count {
            let point = points[index]
            if index < points.count - 1 {
                let next = points[index + 1]
                let midpoint = CGPoint(
                    x: (point.x + next.x) / 2,
                    y: (point.y + next.y) / 2
                )
                path.addQuadCurve(to: midpoint, control: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
}
