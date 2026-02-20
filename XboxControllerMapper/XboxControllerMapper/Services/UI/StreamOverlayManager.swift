import SwiftUI
import AppKit

/// Background style for the stream overlay (for OBS chroma keying)
enum StreamOverlayBackground: String, CaseIterable {
    case semiTransparent = "Semi-Transparent"
    case chromaGreen = "Chroma Green"
    case chromaMagenta = "Chroma Magenta"
    case solid = "Solid Dark"

    var color: Color {
        switch self {
        case .semiTransparent: return .clear
        case .chromaGreen: return Color(red: 0, green: 1, blue: 0)
        case .chromaMagenta: return Color(red: 1, green: 0, blue: 1)
        case .solid: return Color(white: 0.1)
        }
    }
}

/// Manages the floating stream overlay NSPanel
@MainActor
class StreamOverlayManager {
    static let shared = StreamOverlayManager()

    /// Whether the stream overlay is enabled (stored in UserDefaults, defaults to false)
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "streamOverlayEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "streamOverlayEnabled") }
    }

    /// Background style for OBS capture
    static var backgroundStyle: StreamOverlayBackground {
        get {
            let raw = UserDefaults.standard.string(forKey: "streamOverlayBackground") ?? ""
            return StreamOverlayBackground(rawValue: raw) ?? .semiTransparent
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "streamOverlayBackground") }
    }

    private var panel: NSPanel?
    private var hostingView: NSHostingView<StreamOverlayView>?

    /// Saved window positions per display (keyed by CGDirectDisplayID)
    private var savedPositions: [UInt32: NSPoint] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "streamOverlayPositions"),
                  let dict = try? JSONDecoder().decode([UInt32: [CGFloat]].self, from: data) else {
                return [:]
            }
            return dict.mapValues { NSPoint(x: $0[0], y: $0[1]) }
        }
        set {
            let dict = newValue.mapValues { [$0.x, $0.y] }
            if let data = try? JSONEncoder().encode(dict) {
                UserDefaults.standard.set(data, forKey: "streamOverlayPositions")
            }
        }
    }

    private init() {}

    func show(controllerService: ControllerService, inputLogService: InputLogService) {
        if panel != nil { return } // Already showing

        Self.isEnabled = true

        let overlayView = StreamOverlayView(
            controllerService: controllerService,
            inputLogService: inputLogService
        )
        let hosting = NSHostingView(rootView: overlayView)
        let contentSize = NSSize(width: 220, height: 190)
        hosting.frame = NSRect(origin: .zero, size: contentSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.title = "ControllerKeys Overlay"
        panel.contentView = hosting

        // Restore saved position for current display, or center on screen
        if let screen = NSScreen.main {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
            if let savedOrigin = savedPositions[displayID] {
                panel.setFrameOrigin(savedOrigin)
            } else {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.maxX - contentSize.width - 20
                let y = screenFrame.maxY - contentSize.height - 20
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hosting

        // Observe window moves to save position
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: panel
        )
    }

    func hide() {
        Self.isEnabled = false
        saveCurrentPosition()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: panel)
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    func toggle(controllerService: ControllerService, inputLogService: InputLogService) {
        if panel != nil {
            hide()
        } else {
            show(controllerService: controllerService, inputLogService: inputLogService)
        }
    }

    @objc private func windowDidMove(_ notification: Notification) {
        saveCurrentPosition()
    }

    private func saveCurrentPosition() {
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main else { return }
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
        var positions = savedPositions
        positions[displayID] = panel.frame.origin
        savedPositions = positions
    }
}
