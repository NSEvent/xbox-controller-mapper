import SwiftUI
import AppKit
import Combine

/// Manages the floating on-screen keyboard window
@MainActor
class OnScreenKeyboardManager: ObservableObject {
    static let shared = OnScreenKeyboardManager()

    @Published private(set) var isVisible = false

    private var panel: NSPanel?
    private var inputSimulator: InputSimulatorProtocol?
    private var quickTexts: [QuickText] = []
    private var defaultTerminalApp: String = "Terminal"
    private var typingDelay: Double = 0.03
    private var appBarItems: [AppBarItem] = []
    private var websiteLinks: [WebsiteLink] = []
    private var showExtendedFunctionKeys: Bool = false
    private(set) var activateAllWindows: Bool = true
    private var cancellables = Set<AnyCancellable>()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var toggleShortcutKeyCode: UInt16?
    private var toggleShortcutModifiers: ModifierFlags = ModifierFlags()
    /// Saved keyboard positions per screen (session-only, keyed by display ID)
    private var savedPositions: [CGDirectDisplayID: NSPoint] = [:]

    private init() {}

    /// Sets the input simulator to use for sending key presses
    func setInputSimulator(_ simulator: InputSimulatorProtocol) {
        self.inputSimulator = simulator
    }

    /// Configures the global keyboard shortcut for toggling the on-screen keyboard
    func setToggleShortcut(keyCode: UInt16?, modifiers: ModifierFlags) {
        self.toggleShortcutKeyCode = keyCode
        self.toggleShortcutModifiers = modifiers
        updateGlobalMonitor()
    }

    private func updateGlobalMonitor() {
        // Remove existing monitors
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // Only set up monitors if a shortcut is configured
        guard let shortcutKeyCode = toggleShortcutKeyCode else { return }
        guard AXIsProcessTrusted() else { return }

        let expectedMods = toggleShortcutModifiers

        // Global monitor for when other apps are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == shortcutKeyCode else { return }
            let eventMods = ModifierFlags(
                command: event.modifierFlags.contains(.command),
                option: event.modifierFlags.contains(.option),
                shift: event.modifierFlags.contains(.shift),
                control: event.modifierFlags.contains(.control)
            )
            guard eventMods == expectedMods else { return }
            DispatchQueue.main.async {
                self?.toggle()
            }
        }

        // Local monitor for when this app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == shortcutKeyCode else { return event }
            let eventMods = ModifierFlags(
                command: event.modifierFlags.contains(.command),
                option: event.modifierFlags.contains(.option),
                shift: event.modifierFlags.contains(.shift),
                control: event.modifierFlags.contains(.control)
            )
            guard eventMods == expectedMods else { return event }
            DispatchQueue.main.async {
                self?.toggle()
            }
            return nil // Consume the event
        }
    }

    /// Updates the quick texts, app bar items, and website links to display on the keyboard
    func setQuickTexts(_ texts: [QuickText], defaultTerminal: String, typingDelay: Double = 0.03, appBarItems: [AppBarItem] = [], websiteLinks: [WebsiteLink] = [], showExtendedFunctionKeys: Bool = false, activateAllWindows: Bool = true) {
        let changed = self.quickTexts != texts || self.defaultTerminalApp != defaultTerminal || self.appBarItems != appBarItems || self.websiteLinks != websiteLinks || self.showExtendedFunctionKeys != showExtendedFunctionKeys
        self.activateAllWindows = activateAllWindows
        self.quickTexts = texts
        self.defaultTerminalApp = defaultTerminal
        self.typingDelay = typingDelay
        self.appBarItems = appBarItems
        self.websiteLinks = websiteLinks
        self.showExtendedFunctionKeys = showExtendedFunctionKeys

        // Recreate panel if content changed
        if changed && panel != nil {
            let wasVisible = isVisible
            let oldFrame = panel?.frame
            panel?.orderOut(nil)
            panel = nil

            if wasVisible {
                createPanel()
                if let frame = oldFrame {
                    panel?.setFrameOrigin(frame.origin)
                }
                panel?.orderFrontRegardless()
            }
        }
    }

    /// Shows the on-screen keyboard window on the screen where the mouse currently is
    func show() {
        if panel == nil {
            createPanel()
        }
        // Position on the screen where the mouse is
        if let panel = panel {
            let mouseLocation = NSEvent.mouseLocation
            let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
            if let screen = currentScreen {
                let displayID = screen.displayID
                if let savedPosition = savedPositions[displayID] {
                    // Restore saved position for this screen
                    panel.setFrameOrigin(savedPosition)
                } else {
                    // Default: center horizontally, near bottom
                    let screenFrame = screen.visibleFrame
                    let panelSize = panel.frame.size
                    let x = screenFrame.midX - panelSize.width / 2
                    let y = screenFrame.minY + 100
                    panel.setFrameOrigin(NSPoint(x: x, y: y))
                }
            }
        }
        panel?.orderFrontRegardless()
        isVisible = true
    }

    private func createPanel() {
        let keyboardView = OnScreenKeyboardView(
            onKeyPress: { [weak self] keyCode, modifiers in
                self?.handleKeyPress(keyCode: keyCode, modifiers: modifiers)
            },
            onQuickText: { [weak self] quickText in
                self?.handleQuickText(quickText)
            },
            onAppActivate: { [weak self] bundleIdentifier in
                self?.activateApp(bundleIdentifier: bundleIdentifier)
            },
            onWebsiteLinkOpen: { [weak self] url in
                self?.openWebsiteLink(url: url)
            },
            quickTexts: quickTexts,
            appBarItems: appBarItems,
            websiteLinks: websiteLinks,
            showExtendedFunctionKeys: showExtendedFunctionKeys
        )

        let hostingView = NSHostingView(rootView: keyboardView)
        hostingView.setFrameSize(hostingView.fittingSize)

        // Use NSPanel with nonactivatingPanel to avoid stealing focus
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false  // Keep visible when app loses focus
        panel.becomesKeyOnlyIfNeeded = true

        // Center panel on the screen where the mouse cursor currently is
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        if let screen = currentScreen {
            let screenFrame = screen.visibleFrame
            let panelSize = panel.frame.size
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.minY + 100  // Position near bottom of screen
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func recreatePanel() {
        let wasVisible = isVisible
        let oldFrame = panel?.frame
        panel?.orderOut(nil)
        panel = nil

        if wasVisible {
            createPanel()
            if let frame = oldFrame {
                panel?.setFrameOrigin(frame.origin)
            }
            panel?.orderFrontRegardless()
        }
    }

    /// Hides the on-screen keyboard window
    func hide() {
        // Save position for the screen the panel is currently on
        if let panel = panel, let screen = panel.screen ?? NSScreen.main {
            let displayID = screen.displayID
            savedPositions[displayID] = panel.frame.origin
        }
        panel?.orderOut(nil)
        isVisible = false
    }

    /// Toggles the on-screen keyboard visibility
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    private func handleKeyPress(keyCode: CGKeyCode, modifiers: ModifierFlags) {
        guard let simulator = inputSimulator else {
            NSLog("[OnScreenKeyboard] No input simulator configured")
            return
        }

        // Convert ModifierFlags to CGEventFlags
        var eventFlags: CGEventFlags = []
        if modifiers.command { eventFlags.insert(.maskCommand) }
        if modifiers.option { eventFlags.insert(.maskAlternate) }
        if modifiers.shift { eventFlags.insert(.maskShift) }
        if modifiers.control { eventFlags.insert(.maskControl) }

        // Check if this is a mouse click
        if KeyCodeMapping.isMouseButton(keyCode) {
            // Create a temporary mapping for the mouse click
            let mapping = KeyMapping(keyCode: keyCode)
            simulator.executeMapping(mapping)
        } else {
            // Send the key press
            simulator.pressKey(keyCode, modifiers: eventFlags)
        }
    }

    private func handleQuickText(_ quickText: QuickText) {
        NSLog("[OnScreenKeyboard] handleQuickText: '\(quickText.text)', isTerminalCommand: \(quickText.isTerminalCommand)")

        // Expand variables like {date}, {time}, {clipboard}, etc.
        let expandedText = VariableExpander.expand(quickText.text)
        if expandedText != quickText.text {
            NSLog("[OnScreenKeyboard] Expanded to: '\(expandedText)'")
        }

        if quickText.isTerminalCommand {
            executeTerminalCommand(expandedText)
        } else {
            typeText(expandedText)
        }
    }

    /// Activates or hides an app by its bundle identifier
    /// If the app is already focused, it will be hidden. Otherwise, it will be activated.
    private func activateApp(bundleIdentifier: String) {
        NSLog("[OnScreenKeyboard] activateApp called: \(bundleIdentifier)")

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSLog("[OnScreenKeyboard] App not found: \(bundleIdentifier)")
            return
        }

        // Find running instances of the app
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        NSLog("[OnScreenKeyboard] Running instances: \(runningApps.count)")

        // Check if this app is currently the frontmost app
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            NSLog("[OnScreenKeyboard] Frontmost app: \(frontmost.bundleIdentifier ?? "unknown")")
            if frontmost.bundleIdentifier == bundleIdentifier {
                // App is focused - hide it
                NSLog("[OnScreenKeyboard] App is frontmost, hiding: \(bundleIdentifier)")
                frontmost.hide()
                return
            }
        }

        // Use NSWorkspace.shared.openApplication which is reliable for activation
        NSLog("[OnScreenKeyboard] Opening/activating app: \(bundleIdentifier)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = false

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] app, error in
            if let error = error {
                NSLog("[OnScreenKeyboard] Failed to open app: \(error.localizedDescription)")
            } else if let app = app {
                NSLog("[OnScreenKeyboard] Successfully opened: \(app.localizedName ?? bundleIdentifier)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    var options: NSApplication.ActivationOptions = [.activateIgnoringOtherApps]
                    if self?.activateAllWindows == true {
                        options.insert(.activateAllWindows)
                    }
                    app.activate(options: options)
                }
            }
        }
    }

    private func openWebsiteLink(url urlString: String) {
        NSLog("[OnScreenKeyboard] openWebsiteLink: \(urlString)")

        guard let url = URL(string: urlString) else {
            NSLog("[OnScreenKeyboard] Invalid URL: \(urlString)")
            return
        }

        NSWorkspace.shared.open(url)
    }

    /// Types a string of text (paste mode if delay is 0, otherwise character-by-character)
    private func typeText(_ text: String) {
        NSLog("[OnScreenKeyboard] typeText: '\(text)' with delay: \(typingDelay)")

        // If delay is 0, use paste mode (clipboard)
        if typingDelay == 0 {
            pasteText(text)
            return
        }

        let characters = Array(text)
        let delay = typingDelay

        // Type characters on a background queue to avoid blocking
        DispatchQueue.global(qos: .userInitiated).async {
            let source = CGEventSource(stateID: .hidSystemState)

            for (index, char) in characters.enumerated() {
                // Skip unsupported characters
                guard let keyInfo = KeyCodeMapping.keyInfo(for: char) else {
                    NSLog("[OnScreenKeyboard] Skipping unsupported character: '\(char)'")
                    continue
                }

                let keyCode = keyInfo.keyCode
                var flags: CGEventFlags = []
                if keyInfo.needsShift {
                    flags.insert(.maskShift)
                }

                // Create and send key down event
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
                    if !flags.isEmpty {
                        keyDown.flags = flags
                    }
                    keyDown.post(tap: .cghidEventTap)
                }

                // Create and send key up event
                if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                    if !flags.isEmpty {
                        keyUp.flags = flags
                    }
                    keyUp.post(tap: .cghidEventTap)
                }

                // Delay between characters (skip delay after last character)
                if index < characters.count - 1 {
                    Thread.sleep(forTimeInterval: delay)
                }
            }

            NSLog("[OnScreenKeyboard] Finished typing \(characters.count) characters")
        }
    }

    /// Pastes text using clipboard (Cmd+V)
    private func pasteText(_ text: String) {
        NSLog("[OnScreenKeyboard] pasteText: '\(text)'")

        // Save current clipboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set our text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.05)

            // Simulate Cmd+V to paste
            let source = CGEventSource(stateID: .hidSystemState)

            if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),  // 9 = V key
               let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }

            // Restore previous clipboard after a delay
            Thread.sleep(forTimeInterval: 0.3)
            DispatchQueue.main.async {
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }
        }
    }

    /// Executes a command in the terminal using AppleScript
    private func executeTerminalCommand(_ command: String) {
        NSLog("[OnScreenKeyboard] executeTerminalCommand: '\(command)', terminal: \(defaultTerminalApp)")

        // Escape for AppleScript string - need to escape backslashes and quotes
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        var script: String

        switch defaultTerminalApp {
        case "iTerm":
            script = """
            tell application "iTerm"
                activate
                create window with default profile
                delay 0.3
                tell current session of current window
                    write text "\(escapedCommand)"
                end tell
            end tell
            """

        case "Warp":
            script = """
            tell application "Warp"
                activate
                delay 0.5
                tell application "System Events"
                    tell process "Warp"
                        keystroke "t" using command down
                        delay 0.3
                        keystroke "\(escapedCommand)"
                        delay 0.1
                        keystroke return
                    end tell
                end tell
            end tell
            """

        case "Alacritty", "Kitty", "Hyper":
            // For terminals without good AppleScript support, use a workaround
            script = """
            tell application "\(defaultTerminalApp)"
                activate
                delay 0.5
                tell application "System Events"
                    tell process "\(defaultTerminalApp)"
                        keystroke "n" using command down
                        delay 0.3
                        keystroke "\(escapedCommand)"
                        delay 0.1
                        keystroke return
                    end tell
                end tell
            end tell
            """

        default: // Terminal.app
            script = """
            tell application "Terminal"
                activate
                delay 0.2
                do script "\(escapedCommand)"
            end tell
            """
        }

        NSLog("[OnScreenKeyboard] Executing AppleScript:\n\(script)")

        // Run AppleScript on main thread (required for some AppleScript operations)
        DispatchQueue.main.async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                let result = scriptObject.executeAndReturnError(&error)
                if let error = error {
                    NSLog("[OnScreenKeyboard] AppleScript error: \(error)")
                } else {
                    NSLog("[OnScreenKeyboard] AppleScript executed successfully")
                }
            } else {
                NSLog("[OnScreenKeyboard] Failed to create AppleScript object")
            }
        }
    }
}

// MARK: - NSScreen Display ID Helper

extension NSScreen {
    /// The CGDirectDisplayID for this screen
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
