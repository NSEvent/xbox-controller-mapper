import SwiftUI
import AppKit
import Combine

/// Manages the floating directory navigator overlay for file system browsing with a controller
@MainActor
class DirectoryNavigatorManager: ObservableObject {
    static let shared = DirectoryNavigatorManager()

    @Published private(set) var isVisible = false
    @Published private(set) var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published private(set) var currentEntries: [DirectoryEntry] = []
    @Published private(set) var previewEntries: [DirectoryEntry] = []
    @Published var selectedIndex: Int = 0

    var defaultTerminalApp: String = "Terminal"

    private var panel: NSPanel?
    private var clickOutsideMonitor: Any?
    private var localClickMonitor: Any?

    // MARK: - Thread-Safe State

    private nonisolated(unsafe) let stateLock = NSLock()
    private nonisolated(unsafe) var _threadSafeIsVisible = false

    nonisolated var threadSafeIsVisible: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _threadSafeIsVisible
    }

    private func updateThreadSafeState() {
        stateLock.lock()
        _threadSafeIsVisible = isVisible
        stateLock.unlock()
    }

    // MARK: - Computed Properties

    var displayPath: String {
        let path = currentDirectory.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        } else if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Show / Hide / Toggle

    func show() {
        // Mutual exclusivity: hide other overlays
        OnScreenKeyboardManager.shared.hide()
        CommandWheelManager.shared.hide()

        if panel == nil {
            createPanel()
        }

        // Refresh directory contents, preserving selection position
        refreshCurrentDirectory()

        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        if let panel = panel {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
        isVisible = true
        updateThreadSafeState()
        installClickOutsideMonitors()
    }

    func hide() {
        guard isVisible else { return }
        removeClickOutsideMonitors()
        if let panel = panel {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.panel?.orderOut(nil)
            })
        }
        isVisible = false
        updateThreadSafeState()
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    // MARK: - Navigation

    func handleDPadNavigation(_ button: ControllerButton) {
        switch button {
        case .dpadUp:
            moveSelection(by: -1)
        case .dpadDown:
            moveSelection(by: 1)
        case .dpadRight:
            enterDirectory()
        case .dpadLeft:
            goUpDirectory()
        default:
            break
        }
    }

    private func moveSelection(by offset: Int) {
        guard !currentEntries.isEmpty else { return }
        let newIndex = selectedIndex + offset
        if newIndex >= 0 && newIndex < currentEntries.count {
            selectedIndex = newIndex
            updatePreview()
        }
    }

    /// Navigates to a specific directory URL.
    func navigateTo(_ url: URL) {
        loadDirectory(url)
    }

    func enterDirectory() {
        guard selectedIndex < currentEntries.count else { return }
        let entry = currentEntries[selectedIndex]
        guard entry.isDirectory else { return }
        loadDirectory(entry.url)
    }

    func goUpDirectory() {
        let parent = currentDirectory.deletingLastPathComponent()
        // Don't go above root
        guard parent.path != currentDirectory.path else { return }
        let previousDirName = currentDirectory.lastPathComponent
        loadDirectory(parent)
        // Try to select the directory we came from
        if let index = currentEntries.firstIndex(where: { $0.name == previousDirName }) {
            selectedIndex = index
            updatePreview()
        }
    }

    func dismissAndCd() {
        let path = currentDirectory.path
        hide()

        let terminalApp = defaultTerminalApp

        // Escape the path for shell
        let shellEscapedPath = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let command = "cd \"\(shellEscapedPath)\""

        guard let sanitizedTerminalApp = AppleScriptEscaping.sanitizeAppName(terminalApp) else {
            NSLog("[DirectoryNavigator] Terminal app name rejected: %@", terminalApp)
            return
        }

        let escapedCommand = AppleScriptEscaping.escapeForString(command)

        let script: String
        switch sanitizedTerminalApp {
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
            script = """
            tell application "\(sanitizedTerminalApp)"
                activate
                delay 0.5
                tell application "System Events"
                    tell process "\(sanitizedTerminalApp)"
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

        DispatchQueue.main.async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                if let error = error {
                    NSLog("[DirectoryNavigator] AppleScript error: %@", error)
                }
            }
        }
    }

    // MARK: - Mouse Interaction

    /// Selects an entry by index (used for mouse click).
    func selectEntry(at index: Int) {
        guard index >= 0, index < currentEntries.count else { return }
        selectedIndex = index
        updatePreview()
    }

    /// Activates (enters) the entry at the given index (used for mouse double-click).
    func activateEntry(at index: Int) {
        guard index >= 0, index < currentEntries.count else { return }
        selectedIndex = index
        let entry = currentEntries[index]
        if entry.isDirectory {
            loadDirectory(entry.url)
        }
    }

    // MARK: - Click Outside to Dismiss

    private func installClickOutsideMonitors() {
        removeClickOutsideMonitors()

        // Global monitor catches clicks in other apps / desktop
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hide()
            }
        }

        // Local monitor catches clicks within our own app but outside the panel
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }
            if event.window === panel {
                // Click is inside the panel — let it through
                return event
            }
            // Click is in another window or outside — dismiss
            Task { @MainActor in
                self.hide()
            }
            return event
        }
    }

    private func removeClickOutsideMonitors() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    // MARK: - File Enumeration

    /// Refreshes the current directory contents while preserving the selection position.
    private func refreshCurrentDirectory() {
        let previousSelectedName = (selectedIndex < currentEntries.count)
            ? currentEntries[selectedIndex].name : nil

        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: currentDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            currentEntries = []
            previewEntries = []
            selectedIndex = 0
            return
        }

        let entries = urls.map { DirectoryEntry(url: $0) }
        currentEntries = entries.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        // Try to restore selection by name, fall back to clamping index
        if let name = previousSelectedName,
           let index = currentEntries.firstIndex(where: { $0.name == name }) {
            selectedIndex = index
        } else if !currentEntries.isEmpty {
            selectedIndex = min(selectedIndex, currentEntries.count - 1)
        } else {
            selectedIndex = 0
        }

        updatePreview()
    }

    private func loadDirectory(_ url: URL) {
        currentDirectory = url
        selectedIndex = 0

        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            currentEntries = []
            previewEntries = []
            return
        }

        // Build entries
        let entries = urls.map { DirectoryEntry(url: $0) }

        // Sort: directories first, then alphabetical
        currentEntries = entries.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        updatePreview()
    }

    private func updatePreview() {
        guard selectedIndex < currentEntries.count else {
            previewEntries = []
            return
        }

        let selected = currentEntries[selectedIndex]
        guard selected.isDirectory else {
            previewEntries = []
            return
        }

        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: selected.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            previewEntries = []
            return
        }

        let entries = urls.map { DirectoryEntry(url: $0) }
        previewEntries = entries.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Panel Setup

    private func createPanel() {
        let navigatorView = DirectoryNavigatorView(manager: self)
        let hostingView = NSHostingView(rootView: navigatorView)
        let panelWidth: CGFloat = 560
        let panelHeight: CGFloat = 440
        hostingView.setFrameSize(NSSize(width: panelWidth, height: panelHeight))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating + 1
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        // Center on the screen where the mouse is
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        if let screen = currentScreen {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.midY - panelHeight / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
    }
}
