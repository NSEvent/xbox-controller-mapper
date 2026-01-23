import SwiftUI
import AppKit
import Combine

/// Manages the floating command wheel overlay for quick app switching
@MainActor
class CommandWheelManager: ObservableObject {
    static let shared = CommandWheelManager()

    @Published private(set) var isVisible = false
    @Published var selectedIndex: Int?

    private var panel: NSPanel?
    private(set) var appBarItems: [AppBarItem] = []

    /// Deadzone for stick magnitude - below this, no segment is selected
    private let selectionDeadzone: CGFloat = 0.4

    /// Last valid (non-nil) selection index for tolerance on release
    private var lastValidSelection: Int?
    /// Timestamp of the last valid selection
    private var lastValidSelectionTime: TimeInterval = 0
    /// Tolerance window: if stick returns to center within this time, last selection is still used
    private let selectionTolerance: TimeInterval = 0.3

    private init() {}

    /// Prepares the command wheel with app bar items (does NOT show it yet - waits for stick input)
    func prepare(apps: [AppBarItem]) {
        guard !apps.isEmpty else { return }
        self.appBarItems = apps
        self.selectedIndex = nil
        self.lastValidSelection = nil
        self.lastValidSelectionTime = 0
    }

    /// Hides the command wheel
    func hide() {
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
        selectedIndex = nil
        lastValidSelection = nil
        lastValidSelectionTime = 0
    }

    /// Updates the selected segment based on stick position (called at 120Hz from MappingEngine)
    func updateSelection(stickX: CGFloat, stickY: CGFloat) {
        guard !appBarItems.isEmpty else { return }

        let magnitude = sqrt(stickX * stickX + stickY * stickY)
        guard magnitude > selectionDeadzone else {
            // Stick in center - clear current selection but keep lastValidSelection for tolerance
            selectedIndex = nil
            return
        }

        // Show the wheel on first stick movement past deadzone
        if !isVisible {
            showPanel()
        }

        // atan2 gives angle in radians: 0 = right, π/2 = up, -π/2 = down
        // We want "up" to be the first segment, going clockwise
        let angle = atan2(stickY, stickX)
        // Rotate so up (π/2) becomes 0, then flip to clockwise
        var normalizedAngle = -(angle - .pi / 2)
        if normalizedAngle < 0 {
            normalizedAngle += 2 * .pi
        }

        let segmentSize = (2 * CGFloat.pi) / CGFloat(appBarItems.count)
        let index = Int(normalizedAngle / segmentSize) % appBarItems.count
        selectedIndex = index
        lastValidSelection = index
        lastValidSelectionTime = CFAbsoluteTimeGetCurrent()
    }

    /// Activates the currently selected app (if any), with tolerance for recent selections
    func activateSelection() {
        let effectiveSelection: Int?
        if let current = selectedIndex {
            effectiveSelection = current
        } else if let last = lastValidSelection,
                  CFAbsoluteTimeGetCurrent() - lastValidSelectionTime <= selectionTolerance {
            // Stick snapped back to center but selection was recent enough
            effectiveSelection = last
        } else {
            effectiveSelection = nil
        }

        guard let index = effectiveSelection, index < appBarItems.count else { return }
        let item = appBarItems[index]
        activateApp(bundleIdentifier: item.bundleIdentifier)
    }

    private func showPanel() {
        if panel == nil {
            createPanel()
        }
        panel?.orderFrontRegardless()
        isVisible = true
    }

    private func createPanel() {
        let wheelView = CommandWheelView(manager: self)
        let hostingView = NSHostingView(rootView: wheelView)
        let size: CGFloat = 300
        hostingView.setFrameSize(NSSize(width: size, height: size))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: size, height: size)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating + 1  // Above the keyboard panel
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        // Center on the screen where the mouse is
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        if let screen = currentScreen {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - size / 2
            let y = screenFrame.midY - size / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
    }

    private func activateApp(bundleIdentifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        let allWindows = OnScreenKeyboardManager.shared.activateAllWindows

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = false

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, _ in
            if let app = app {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    var options: NSApplication.ActivationOptions = [.activateIgnoringOtherApps]
                    if allWindows {
                        options.insert(.activateAllWindows)
                    }
                    app.activate(options: options)
                }
            }
        }
    }
}
