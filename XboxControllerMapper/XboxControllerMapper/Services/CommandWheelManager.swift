import SwiftUI
import AppKit
import Combine

/// An item displayed in the command wheel
struct CommandWheelItem: Identifiable {
    let id: UUID
    let displayName: String
    let kind: Kind

    enum Kind {
        case app(bundleIdentifier: String)
        case website(url: String, faviconData: Data?)
    }
}

/// Manages the floating command wheel overlay for quick app/website switching
@MainActor
class CommandWheelManager: ObservableObject {
    static let shared = CommandWheelManager()

    @Published private(set) var isVisible = false
    @Published var selectedIndex: Int?
    /// Progress of force quit fill (0.0 to 1.0), only for apps
    @Published private(set) var forceQuitProgress: CGFloat = 0

    private var panel: NSPanel?
    private(set) var items: [CommandWheelItem] = []
    private var primaryItems: [CommandWheelItem] = []
    private var alternateItems: [CommandWheelItem] = []
    private(set) var isShowingAlternate = false

    /// Deadzone for stick magnitude - below this, no segment is selected
    private let selectionDeadzone: CGFloat = 0.4
    /// Threshold for "full range" stick position
    private let fullRangeThreshold: CGFloat = 0.92
    /// Duration to hold at full range before force quit is ready (seconds)
    private let forceQuitDuration: TimeInterval = 1.0

    /// Whether the stick is currently at full range
    private(set) var isFullRange = false
    /// When the stick first hit full range on the current segment
    private var fullRangeStartTime: TimeInterval?
    /// The segment index when full range started (reset if segment changes)
    private var fullRangeSegment: Int?

    /// Last valid (non-nil) selection index for tolerance on release
    private var lastValidSelection: Int?
    /// Whether the last valid selection was at full range
    private var lastValidFullRange = false
    /// Timestamp of the last valid selection
    private var lastValidSelectionTime: TimeInterval = 0
    /// Tolerance window: if stick returns to center within this time, last selection is still used
    private let selectionTolerance: TimeInterval = 0.3
    /// Tolerance for modifier release: don't swap back to primary immediately
    private let alternateReleaseTolerance: TimeInterval = 0.3
    /// When the alternate modifier was released (nil = not pending swap back)
    private var alternateReleaseTime: TimeInterval?
    /// Callback fired when the selected segment changes (used for haptic feedback)
    var onSegmentChanged: (() -> Void)?
    /// Callback fired when crossing the perimeter boundary (inner↔outer transition)
    var onPerimeterCrossed: (() -> Void)?
    /// Callback fired when force quit is ready (progress reaches 1.0)
    var onForceQuitReady: (() -> Void)?
    /// Previous segment index for detecting changes
    private var previousSegmentIndex: Int?
    /// Previous full range state for detecting inner↔outer transitions
    private var previousIsFullRange = false
    /// Whether the force quit haptic has already been fired for the current hold
    private var forceQuitHapticFired = false

    private init() {}

    /// Prepares the command wheel with primary and alternate item sets (does NOT show it yet - waits for stick input)
    func prepare(apps: [AppBarItem], websites: [WebsiteLink], showWebsitesFirst: Bool) {
        let appItems = apps.map { app in
            CommandWheelItem(id: app.id, displayName: app.displayName, kind: .app(bundleIdentifier: app.bundleIdentifier))
        }
        let websiteItems = websites.map { link in
            CommandWheelItem(id: link.id, displayName: link.displayName, kind: .website(url: link.url, faviconData: link.faviconData))
        }
        if showWebsitesFirst {
            primaryItems = websiteItems
            alternateItems = appItems
        } else {
            primaryItems = appItems
            alternateItems = websiteItems
        }
        isShowingAlternate = false
        alternateReleaseTime = nil
        items = primaryItems.isEmpty ? alternateItems : primaryItems
        selectedIndex = nil
        previousSegmentIndex = nil
        previousIsFullRange = false
        lastValidSelection = nil
        lastValidSelectionTime = 0
        lastValidFullRange = false
        resetForceQuit()
    }

    /// Switches between primary and alternate items based on modifier state
    func setShowingAlternate(_ alternate: Bool) {
        if alternate {
            // Switching to alternate: do it immediately, cancel any pending swap-back
            alternateReleaseTime = nil
            guard !isShowingAlternate else { return }
            isShowingAlternate = true
            guard !alternateItems.isEmpty else { return }
            items = alternateItems
            selectedIndex = nil
            lastValidSelection = nil
            lastValidSelectionTime = 0
            lastValidFullRange = false
            resetForceQuit()
        } else {
            // Switching back to primary: delay to allow simultaneous release
            guard isShowingAlternate else { return }
            if alternateReleaseTime == nil {
                alternateReleaseTime = CFAbsoluteTimeGetCurrent()
            }
        }
    }

    /// Called from updateSelection to check if pending swap-back should execute
    private func checkAlternateRelease() {
        guard let releaseTime = alternateReleaseTime else { return }
        if CFAbsoluteTimeGetCurrent() - releaseTime > alternateReleaseTolerance {
            alternateReleaseTime = nil
            isShowingAlternate = false
            guard !primaryItems.isEmpty else { return }
            items = primaryItems
            selectedIndex = nil
            lastValidSelection = nil
            lastValidSelectionTime = 0
            lastValidFullRange = false
            resetForceQuit()
        }
    }

    /// Hides the command wheel
    func hide() {
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
        selectedIndex = nil
        previousSegmentIndex = nil
        previousIsFullRange = false
        lastValidSelection = nil
        lastValidSelectionTime = 0
        lastValidFullRange = false
        alternateReleaseTime = nil
        resetForceQuit()
    }

    private func resetForceQuit() {
        isFullRange = false
        fullRangeStartTime = nil
        fullRangeSegment = nil
        forceQuitProgress = 0
        forceQuitHapticFired = false
    }

    /// Updates the selected segment based on stick position (called at 120Hz from MappingEngine)
    func updateSelection(stickX: CGFloat, stickY: CGFloat) {
        guard !items.isEmpty else { return }
        checkAlternateRelease()

        let magnitude = sqrt(stickX * stickX + stickY * stickY)
        guard magnitude > selectionDeadzone else {
            // Stick in center - fire haptic if coming from a selection
            if previousSegmentIndex != nil {
                previousSegmentIndex = nil
                onSegmentChanged?()
            }
            if previousIsFullRange {
                previousIsFullRange = false
                onPerimeterCrossed?()
            }
            selectedIndex = nil
            isFullRange = false
            fullRangeStartTime = nil
            fullRangeSegment = nil
            forceQuitProgress = 0
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

        let segmentSize = (2 * CGFloat.pi) / CGFloat(items.count)
        let index = Int(normalizedAngle / segmentSize) % items.count
        if index != previousSegmentIndex {
            previousSegmentIndex = index
            onSegmentChanged?()
        }
        selectedIndex = index
        lastValidSelection = index
        lastValidSelectionTime = CFAbsoluteTimeGetCurrent()

        // Track full range state
        let atFullRange = magnitude >= fullRangeThreshold
        if atFullRange != previousIsFullRange {
            onPerimeterCrossed?()
        }
        previousIsFullRange = atFullRange
        isFullRange = atFullRange
        lastValidFullRange = atFullRange

        if atFullRange {
            // Check if this is a new segment or first time at full range
            if fullRangeSegment != index {
                fullRangeStartTime = CFAbsoluteTimeGetCurrent()
                fullRangeSegment = index
                forceQuitProgress = 0
                forceQuitHapticFired = false
            }
            // Update long-hold progress (force quit for apps, incognito for websites)
            if let startTime = fullRangeStartTime {
                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                forceQuitProgress = min(1.0, CGFloat(elapsed / forceQuitDuration))
                if forceQuitProgress >= 1.0 && !forceQuitHapticFired {
                    forceQuitHapticFired = true
                    onForceQuitReady?()
                }
            }
        } else {
            // Not at full range - reset force quit tracking
            fullRangeStartTime = nil
            fullRangeSegment = nil
            forceQuitProgress = 0
        }
    }

    /// Activates the currently selected item (if any), with tolerance for recent selections
    func activateSelection() {
        let effectiveSelection: Int?
        let effectiveFullRange: Bool
        if let current = selectedIndex {
            effectiveSelection = current
            effectiveFullRange = isFullRange
        } else if let last = lastValidSelection,
                  CFAbsoluteTimeGetCurrent() - lastValidSelectionTime <= selectionTolerance {
            effectiveSelection = last
            effectiveFullRange = lastValidFullRange
        } else {
            effectiveSelection = nil
            effectiveFullRange = false
        }

        guard let index = effectiveSelection, index < items.count else { return }
        let item = items[index]

        // Check for long-hold actions (progress must be complete)
        if forceQuitProgress >= 1.0 {
            switch item.kind {
            case .app(let bundleIdentifier):
                forceQuitApp(bundleIdentifier: bundleIdentifier)
            case .website(let url, _):
                openWebsiteIncognito(url: url)
            }
            return
        }

        // Full range = open new window; normal = activate/open
        if effectiveFullRange {
            switch item.kind {
            case .app(let bundleIdentifier):
                openNewWindow(bundleIdentifier: bundleIdentifier)
            case .website(let url, _):
                openWebsite(url: url)
            }
        } else {
            switch item.kind {
            case .app(let bundleIdentifier):
                activateApp(bundleIdentifier: bundleIdentifier)
            case .website(let url, _):
                openWebsite(url: url)
            }
        }
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
        let size: CGFloat = 920
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

        // If the app is already frontmost, hide it instead
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier == bundleIdentifier {
            frontmost.hide()
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

    private func openNewWindow(bundleIdentifier: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return
        }

        let allWindows = OnScreenKeyboardManager.shared.activateAllWindows

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = false

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, _ in
            if let app = app {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    var options: NSApplication.ActivationOptions = [.activateIgnoringOtherApps]
                    if allWindows {
                        options.insert(.activateAllWindows)
                    }
                    app.activate(options: options)
                    // Send Cmd+N to open a new window
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        let source = CGEventSource(stateID: .hidSystemState)
                        // Key down: N (keycode 45) with Cmd
                        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: true)
                        keyDown?.flags = .maskCommand
                        keyDown?.post(tap: .cghidEventTap)
                        // Key up
                        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 45, keyDown: false)
                        keyUp?.flags = .maskCommand
                        keyUp?.post(tap: .cghidEventTap)
                    }
                }
            }
        }
    }

    private func forceQuitApp(bundleIdentifier: String) {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        for app in runningApps {
            app.forceTerminate()
        }
    }

    private func openWebsite(url urlString: String) {
        var urlStr = urlString
        if !urlStr.contains("://") {
            urlStr = "https://\(urlStr)"
        }
        guard let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openWebsiteIncognito(url urlString: String) {
        var urlStr = urlString
        if !urlStr.contains("://") {
            urlStr = "https://\(urlStr)"
        }

        // Determine the default browser
        let defaultBrowser = LSCopyDefaultHandlerForURLScheme("https" as CFString)?.takeRetainedValue() as String? ?? ""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        switch defaultBrowser {
        case let id where id.contains("com.google.Chrome"):
            process.arguments = ["-na", "Google Chrome", "--args", "--incognito", urlStr]
        case let id where id.contains("com.brave.Browser"):
            process.arguments = ["-na", "Brave Browser", "--args", "--incognito", urlStr]
        case let id where id.contains("com.microsoft.edgemac"):
            process.arguments = ["-na", "Microsoft Edge", "--args", "--inprivate", urlStr]
        case let id where id.contains("company.thebrowser.Browser"):
            process.arguments = ["-na", "Arc", "--args", "--incognito", urlStr]
        case let id where id.contains("com.vivaldi.Vivaldi"):
            process.arguments = ["-na", "Vivaldi", "--args", "--incognito", urlStr]
        case let id where id.contains("org.mozilla.firefox"):
            process.arguments = ["-na", "Firefox", "--args", "--private-window", urlStr]
        case let id where id.contains("com.apple.Safari"):
            // Safari: use AppleScript to open a private window
            let script = """
            tell application "Safari"
                activate
                delay 0.3
                tell application "System Events" to keystroke "n" using {command down, shift down}
                delay 0.5
                set URL of current tab of front window to "\(urlStr)"
            end tell
            """
            let appleScript = Process()
            appleScript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            appleScript.arguments = ["-e", script]
            try? appleScript.run()
            return
        default:
            // Fallback: just open normally if browser is unknown
            if let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        try? process.run()
    }
}
