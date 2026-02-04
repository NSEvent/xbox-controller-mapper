import SwiftUI
import AppKit
import Combine

/// Represents a highlighted item in the on-screen keyboard navigation
enum KeyboardNavigationItem: Hashable {
    /// Keyboard key identified by row and column (not key code, to handle duplicates like left/right shift)
    case keyPosition(row: Int, column: Int)
    case appBarItem(UUID)
    case websiteLink(UUID)
    case quickText(UUID)
}

/// Manages the floating on-screen keyboard window
@MainActor
class OnScreenKeyboardManager: ObservableObject {
    static let shared = OnScreenKeyboardManager()

    @Published private(set) var isVisible = false

    // MARK: - D-Pad Navigation State
    @Published var navigationModeActive = false
    @Published var highlightedItem: KeyboardNavigationItem?

    /// Last item hovered by mouse - used as starting position when entering D-pad navigation
    var lastMouseHoveredItem: KeyboardNavigationItem?

    /// Convenience accessor for highlighted key code (looks up from position)
    var highlightedKeyCode: CGKeyCode? {
        if case .keyPosition(let row, let column) = highlightedItem {
            // Check if this is a navigation column key (column >= 100)
            if column >= 100 {
                let navIndex = column - 100
                let navColumn = KeyboardNavigationMap.navigationColumn
                if navIndex >= 0 && navIndex < navColumn.count {
                    return navColumn[navIndex].keyCode
                }
                return nil
            }

            let keyboardRows = getKeyboardRows()
            if row >= 0 && row < keyboardRows.count {
                let keyRow = keyboardRows[row]
                if column >= 0 && column < keyRow.count {
                    return keyRow[column].keyCode
                }
            }
        }
        return nil
    }

    /// Get the highlighted keyboard position (row, column) if a keyboard key is highlighted
    var highlightedKeyPosition: (row: Int, column: Int)? {
        if case .keyPosition(let row, let column) = highlightedItem {
            return (row, column)
        }
        return nil
    }

    /// Convenience accessor for highlighted app bar item ID
    var highlightedAppBarItemId: UUID? {
        if case .appBarItem(let id) = highlightedItem {
            return id
        }
        return nil
    }

    /// Convenience accessor for highlighted website link ID
    var highlightedWebsiteLinkId: UUID? {
        if case .websiteLink(let id) = highlightedItem {
            return id
        }
        return nil
    }

    /// Convenience accessor for highlighted quick text ID
    var highlightedQuickTextId: UUID? {
        if case .quickText(let id) = highlightedItem {
            return id
        }
        return nil
    }

    /// Check if a specific keyboard row/column position is highlighted
    /// Used by the view for keys with duplicate key codes (e.g., left/right shift)
    func isKeyboardPositionHighlighted(keyboardRow: Int, column: Int) -> Bool {
        guard case .keyPosition(let row, let col) = highlightedItem else { return false }
        return row == keyboardRow && col == column
    }

    // MARK: - Mouse Hover Tracking

    /// Set the last mouse-hovered keyboard key by position
    func setMouseHoveredKeyPosition(row: Int, column: Int) {
        lastMouseHoveredItem = .keyPosition(row: row, column: column)
    }

    /// Set the last mouse-hovered keyboard key by key code (finds position in navigation map)
    func setMouseHoveredKey(_ keyCode: CGKeyCode?) {
        guard let keyCode = keyCode else {
            // Don't clear - keep last position for D-pad to start from
            return
        }
        // Find the position of this key code in the keyboard rows
        let keyboardRows = getKeyboardRows()
        for (rowIndex, row) in keyboardRows.enumerated() {
            for (colIndex, position) in row.enumerated() {
                if position.keyCode == keyCode {
                    lastMouseHoveredItem = .keyPosition(row: rowIndex, column: colIndex)
                    return
                }
            }
        }
    }

    /// Set the last mouse-hovered app bar item
    func setMouseHoveredAppBarItem(_ id: UUID?) {
        guard let id = id else { return }
        lastMouseHoveredItem = .appBarItem(id)
    }

    /// Set the last mouse-hovered website link
    func setMouseHoveredWebsiteLink(_ id: UUID?) {
        guard let id = id else { return }
        lastMouseHoveredItem = .websiteLink(id)
    }

    /// Set the last mouse-hovered quick text
    func setMouseHoveredQuickText(_ id: UUID?) {
        guard let id = id else { return }
        lastMouseHoveredItem = .quickText(id)
    }

    private var cursorHidden = false
    private var mouseMovementMonitor: Any?
    private var localMouseMovementMonitor: Any?

    // MARK: - Thread-Safe State Accessors
    /// Lock for thread-safe access to state from non-main threads
    private nonisolated(unsafe) let stateLock = NSLock()
    private nonisolated(unsafe) var _threadSafeIsVisible = false
    private nonisolated(unsafe) var _threadSafeNavigationModeActive = false
    private nonisolated(unsafe) var _threadSafeHighlightedItem: KeyboardNavigationItem?

    /// Thread-safe accessor for keyboard visibility (can be called from any thread)
    nonisolated var threadSafeIsVisible: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _threadSafeIsVisible
    }

    /// Thread-safe accessor for navigation mode (can be called from any thread)
    nonisolated var threadSafeNavigationModeActive: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _threadSafeNavigationModeActive
    }

    /// Thread-safe accessor for highlighted item (can be called from any thread)
    nonisolated var threadSafeHighlightedItem: KeyboardNavigationItem? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _threadSafeHighlightedItem
    }

    /// Update thread-safe visibility state (call from main thread)
    private func updateThreadSafeState() {
        stateLock.lock()
        _threadSafeIsVisible = isVisible
        _threadSafeNavigationModeActive = navigationModeActive
        _threadSafeHighlightedItem = highlightedItem
        stateLock.unlock()
    }

    /// Synchronously update thread-safe highlighted item and trigger main thread update
    private func setHighlightedItemSync(_ item: KeyboardNavigationItem?) {
        stateLock.lock()
        _threadSafeHighlightedItem = item
        _threadSafeNavigationModeActive = true
        stateLock.unlock()

        // Update @Published on main thread for SwiftUI
        highlightedItem = item
        if !navigationModeActive {
            navigationModeActive = true
        }
    }

    private var panel: NSPanel?
    private var inputSimulator: InputSimulatorProtocol?
    private var quickTexts: [QuickText] = []
    private var defaultTerminalApp: String = "Terminal"
    private var typingDelay: Double = 0.03
    private var appBarItems: [AppBarItem] = []
    private var websiteLinks: [WebsiteLink] = []
    private var showExtendedFunctionKeys: Bool = false
    private(set) var activateAllWindows: Bool = true
    private var hapticHandler: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var toggleShortcutKeyCode: UInt16?
    private var toggleShortcutModifiers: ModifierFlags = ModifierFlags()
    /// Saved keyboard positions per screen (session-only, keyed by display ID)
    private var savedPositions: [CGDirectDisplayID: NSPoint] = [:]

    // MARK: - Navigation Grid Cache
    /// Cached navigation grid to avoid rebuilding on every D-pad press
    private var cachedNavigationGrid: [[KeyboardNavigationItem]]?
    private var cachedKeyboardStartRow: Int = 0
    /// Cached keyboard rows from KeyboardNavigationMap
    private var cachedKeyboardRows: [[KeyboardNavigationMap.KeyPosition]]?
    /// Invalidate cache when content changes
    private var navigationGridNeedsRebuild = true

    private init() {}

    /// Sets the input simulator to use for sending key presses
    func setInputSimulator(_ simulator: InputSimulatorProtocol) {
        self.inputSimulator = simulator
    }

    /// Sets a haptic callback for on-screen keyboard actions
    func setHapticHandler(_ handler: (() -> Void)?) {
        self.hapticHandler = handler
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

        // Invalidate navigation grid cache when content changes
        if changed {
            invalidateNavigationGridCache()
        }

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
        updateThreadSafeState()
    }

    private func createPanel() {
        let keyboardView = OnScreenKeyboardView(
            onKeyPress: { [weak self] keyCode, modifiers in
                self?.handleKeyPress(keyCode: keyCode, modifiers: modifiers)
                self?.hapticHandler?()
            },
            onQuickText: { [weak self] quickText in
                self?.handleQuickText(quickText)
                self?.hapticHandler?()
            },
            onAppActivate: { [weak self] bundleIdentifier in
                self?.activateApp(bundleIdentifier: bundleIdentifier)
                self?.hapticHandler?()
            },
            onWebsiteLinkOpen: { [weak self] url in
                self?.openWebsiteLink(url: url)
                self?.hapticHandler?()
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
        // Exit navigation mode first
        exitNavigationMode()

        // Save position for the screen the panel is currently on
        if let panel = panel, let screen = panel.screen ?? NSScreen.main {
            let displayID = screen.displayID
            savedPositions[displayID] = panel.frame.origin
        }
        panel?.orderOut(nil)
        isVisible = false
        updateThreadSafeState()
    }

    // MARK: - D-Pad Navigation

    /// Number of items per row in app bar and website sections
    private let itemsPerRow = 12

    /// Handle D-pad navigation input
    func handleDPadNavigation(_ direction: ControllerButton) {
        // Enter navigation mode if not already active
        if !navigationModeActive {
            enterNavigationMode()
        }

        let previousItem = highlightedItem

        // Disable animations for faster highlight updates
        var transaction = Transaction()
        transaction.disablesAnimations = true

        withTransaction(transaction) {
            // Navigate based on current item type and direction
            switch direction {
            case .dpadUp:
                navigateUp()
            case .dpadDown:
                navigateDown()
            case .dpadLeft:
                navigateLeft()
            case .dpadRight:
                navigateRight()
            default:
                return
            }
        }

        // Update thread-safe state immediately
        updateThreadSafeState()

        // Play haptic feedback if item changed
        if highlightedItem != previousItem {
            hapticHandler?()
        }
    }

    /// Activate the currently highlighted item
    func activateHighlightedItem() {
        guard navigationModeActive, let item = highlightedItem else { return }

        switch item {
        case .keyPosition(let row, let column):
            // Check if this is a navigation column key (column >= 100)
            if column >= 100 {
                let navIndex = column - 100
                let navColumn = KeyboardNavigationMap.navigationColumn
                if navIndex >= 0 && navIndex < navColumn.count {
                    let keyCode = navColumn[navIndex].keyCode
                    handleKeyPress(keyCode: keyCode, modifiers: ModifierFlags())
                }
            } else {
                // Look up the key code from the position
                let keyboardRows = getKeyboardRows()
                if row >= 0 && row < keyboardRows.count {
                    let keyRow = keyboardRows[row]
                    if column >= 0 && column < keyRow.count {
                        let keyCode = keyRow[column].keyCode
                        handleKeyPress(keyCode: keyCode, modifiers: ModifierFlags())
                    }
                }
            }
        case .appBarItem(let id):
            if let appItem = appBarItems.first(where: { $0.id == id }) {
                activateApp(bundleIdentifier: appItem.bundleIdentifier)
            }
        case .websiteLink(let id):
            if let link = websiteLinks.first(where: { $0.id == id }) {
                openWebsiteLink(url: link.url)
            }
        case .quickText(let id):
            if let quickText = quickTexts.first(where: { $0.id == id }) {
                handleQuickText(quickText)
            }
        }
        hapticHandler?()
    }

    /// Legacy method for backward compatibility
    func activateHighlightedKey() {
        activateHighlightedItem()
    }

    /// Enter navigation mode - hide cursor and start mouse monitor
    private func enterNavigationMode() {
        guard !navigationModeActive else { return }
        navigationModeActive = true
        updateThreadSafeState()

        // Set initial highlighted item - use last mouse hovered position if available
        if highlightedItem == nil {
            if let lastHovered = lastMouseHoveredItem {
                highlightedItem = lastHovered
            } else {
                highlightedItem = getDefaultItem()
            }
        }

        // Hide cursor
        if !cursorHidden {
            NSCursor.hide()
            cursorHidden = true
        }

        // Start monitoring mouse movement to exit navigation mode
        startMouseMovementMonitor()
    }

    /// Exit navigation mode - show cursor and clear highlight
    func exitNavigationMode() {
        guard navigationModeActive else { return }
        navigationModeActive = false
        highlightedItem = nil
        updateThreadSafeState()

        // Show cursor if it was hidden
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }

        // Stop mouse movement monitor
        stopMouseMovementMonitor()
    }

    // MARK: - Navigation Helpers

    /// Invalidate the navigation grid cache (call when content changes)
    private func invalidateNavigationGridCache() {
        cachedNavigationGrid = nil
        cachedKeyboardRows = nil
        navigationGridNeedsRebuild = true
    }

    /// Get cached keyboard rows
    private func getKeyboardRows() -> [[KeyboardNavigationMap.KeyPosition]] {
        if let cached = cachedKeyboardRows, !navigationGridNeedsRebuild {
            return cached
        }
        let rows = KeyboardNavigationMap.allRows(includeExtendedFunctions: showExtendedFunctionKeys)
        cachedKeyboardRows = rows
        return rows
    }

    /// Get the navigation grid (uses cache if available)
    private func getNavigationGrid() -> (grid: [[KeyboardNavigationItem]], keyboardStartRow: Int) {
        if let cached = cachedNavigationGrid, !navigationGridNeedsRebuild {
            return (cached, cachedKeyboardStartRow)
        }

        let result = buildNavigationGridInternal()
        cachedNavigationGrid = result.grid
        cachedKeyboardStartRow = result.keyboardStartRow
        navigationGridNeedsRebuild = false
        return result
    }

    /// Build the navigation grid representing all rows in visual order
    /// Returns the grid and the starting row index for keyboard keys
    private func buildNavigationGridInternal() -> (grid: [[KeyboardNavigationItem]], keyboardStartRow: Int) {
        var grid: [[KeyboardNavigationItem]] = []

        // Website links rows (top)
        if !websiteLinks.isEmpty {
            let rows = websiteLinks.chunked(into: itemsPerRow)
            for row in rows {
                grid.append(row.map { .websiteLink($0.id) })
            }
        }

        // App bar rows
        if !appBarItems.isEmpty {
            let rows = appBarItems.chunked(into: itemsPerRow)
            for row in rows {
                grid.append(row.map { .appBarItem($0.id) })
            }
        }

        // Quick text rows (terminal commands first, then text snippets)
        let terminalCommands = quickTexts.filter { $0.isTerminalCommand }
        let textSnippets = quickTexts.filter { !$0.isTerminalCommand }

        if !terminalCommands.isEmpty {
            grid.append(terminalCommands.map { .quickText($0.id) })
        }
        if !textSnippets.isEmpty {
            grid.append(textSnippets.map { .quickText($0.id) })
        }

        // Track where keyboard rows start in the grid
        let keyboardStartRow = grid.count

        // Keyboard rows from KeyboardNavigationMap - use position-based items
        let keyboardRows = KeyboardNavigationMap.allRows(includeExtendedFunctions: showExtendedFunctionKeys)
        for (rowIndex, row) in keyboardRows.enumerated() {
            grid.append(row.enumerated().map { (colIndex, _) in
                .keyPosition(row: rowIndex, column: colIndex)
            })
        }

        // Add navigation column keys to the appropriate rows
        // Navigation column has 5 keys (Del, Home, End, PgUp, PgDn) that align with:
        // number row, qwerty row, asdf row, zxcv row, bottom row
        // These are the last 5 rows in the keyboard section
        let navColumn = KeyboardNavigationMap.navigationColumn
        let keyboardRowCount = keyboardRows.count
        for (navIndex, _) in navColumn.enumerated() {
            // Navigation keys align with the last 5 keyboard rows
            let targetKeyboardRow = keyboardRowCount - 5 + navIndex
            let targetGridRow = keyboardStartRow + targetKeyboardRow
            if targetGridRow >= 0 && targetGridRow < grid.count {
                // Use column 100 + navIndex to indicate navigation column
                grid[targetGridRow].append(.keyPosition(row: targetKeyboardRow, column: 100 + navIndex))
            }
        }

        return (grid, keyboardStartRow)
    }

    /// Find current position in the navigation grid
    private func findCurrentPosition(in grid: [[KeyboardNavigationItem]]) -> (row: Int, col: Int)? {
        guard let current = highlightedItem else { return nil }
        for (rowIndex, row) in grid.enumerated() {
            for (colIndex, item) in row.enumerated() {
                if item == current {
                    return (rowIndex, colIndex)
                }
            }
        }
        return nil
    }

    /// Get the default starting position (F key - between D and G)
    private func getDefaultItem() -> KeyboardNavigationItem {
        // F key is in the ASDF row
        // Row indices: media=0, extended(if enabled)=1, function=1/2, number=2/3, qwerty=3/4, asdf=4/5
        let asdfRowIndex = showExtendedFunctionKeys ? 5 : 4
        // F is at column 4 in the ASDF row (Caps=0, A=1, S=2, D=3, F=4)
        return .keyPosition(row: asdfRowIndex, column: 4)
    }

    private func navigateUp() {
        let (grid, keyboardStartRow) = getNavigationGrid()
        guard !grid.isEmpty else { return }

        if let (row, col) = findCurrentPosition(in: grid) {
            if row > 0 {
                let targetRow = grid[row - 1]
                let currentRow = grid[row]

                // Check if current item is in navigation column (column >= 100)
                if case .keyPosition(_, let keyCol) = currentRow[col], keyCol >= 100 {
                    // Stay in navigation column - find nav item in target row
                    if let navItem = targetRow.first(where: {
                        if case .keyPosition(_, let c) = $0 { return c >= 100 }
                        return false
                    }) {
                        highlightedItem = navItem
                        return
                    }
                }

                // For keyboard rows, use xPosition-based matching
                if row >= keyboardStartRow && row - 1 >= keyboardStartRow {
                    if let closestItem = findClosestKeyByXPosition(in: targetRow, currentItem: currentRow[col]) {
                        highlightedItem = closestItem
                        return
                    }
                }

                // For all rows, use proportional position matching
                let closestCol = findClosestColumnByProportion(currentCol: col, currentRowCount: currentRow.count, targetRowCount: targetRow.count)
                highlightedItem = targetRow[closestCol]
            }
        } else {
            highlightedItem = getDefaultItem()
        }
    }

    private func navigateDown() {
        let (grid, keyboardStartRow) = getNavigationGrid()
        guard !grid.isEmpty else { return }

        if let (row, col) = findCurrentPosition(in: grid) {
            if row < grid.count - 1 {
                let targetRow = grid[row + 1]
                let currentRow = grid[row]

                // Check if current item is in navigation column (column >= 100)
                if case .keyPosition(_, let keyCol) = currentRow[col], keyCol >= 100 {
                    // Stay in navigation column - find nav item in target row
                    if let navItem = targetRow.first(where: {
                        if case .keyPosition(_, let c) = $0 { return c >= 100 }
                        return false
                    }) {
                        highlightedItem = navItem
                        return
                    }
                }

                // For keyboard rows, use xPosition-based matching
                if row >= keyboardStartRow && row + 1 >= keyboardStartRow {
                    if let closestItem = findClosestKeyByXPosition(in: targetRow, currentItem: currentRow[col]) {
                        highlightedItem = closestItem
                        return
                    }
                }

                // For all rows, use proportional position matching
                let closestCol = findClosestColumnByProportion(currentCol: col, currentRowCount: currentRow.count, targetRowCount: targetRow.count)
                highlightedItem = targetRow[closestCol]
            }
        } else {
            highlightedItem = getDefaultItem()
        }
    }

    /// Find the closest column in target row based on proportional position
    private func findClosestColumnByProportion(currentCol: Int, currentRowCount: Int, targetRowCount: Int) -> Int {
        guard currentRowCount > 0 && targetRowCount > 0 else { return 0 }

        // Calculate proportional position (0.0 to 1.0)
        let proportion = Double(currentCol) / Double(max(1, currentRowCount - 1))

        // Map to target row
        let targetCol = Int(round(proportion * Double(max(1, targetRowCount - 1))))
        return min(targetCol, targetRowCount - 1)
    }

    /// Find the closest keyboard key in the target row by xPosition
    private func findClosestKeyByXPosition(in targetRow: [KeyboardNavigationItem], currentItem: KeyboardNavigationItem) -> KeyboardNavigationItem? {
        // Get current item's xPosition
        guard case .keyPosition(let currentKeyRow, let currentKeyCol) = currentItem else {
            return nil
        }

        let keyboardRows = getKeyboardRows()
        let currentXPosition: Double

        if currentKeyCol >= 100 {
            // Navigation column - use xPosition 1.0
            currentXPosition = 1.0
        } else if currentKeyRow >= 0 && currentKeyRow < keyboardRows.count {
            let row = keyboardRows[currentKeyRow]
            if currentKeyCol >= 0 && currentKeyCol < row.count {
                currentXPosition = row[currentKeyCol].xPosition
            } else {
                return nil
            }
        } else {
            return nil
        }

        // Find closest item in target row by xPosition (only consider keyboard keys, not nav column)
        var closestItem: KeyboardNavigationItem?
        var closestDistance: Double = .infinity

        for item in targetRow {
            guard case .keyPosition(let targetKeyRow, let targetKeyCol) = item else {
                continue
            }
            // Skip navigation column items
            if targetKeyCol >= 100 {
                continue
            }
            guard targetKeyRow >= 0 && targetKeyRow < keyboardRows.count else {
                continue
            }
            let row = keyboardRows[targetKeyRow]
            guard targetKeyCol >= 0 && targetKeyCol < row.count else {
                continue
            }

            let targetXPosition = row[targetKeyCol].xPosition
            let distance = abs(targetXPosition - currentXPosition)
            if distance < closestDistance {
                closestDistance = distance
                closestItem = item
            }
        }

        return closestItem
    }

    private func navigateLeft() {
        let (grid, _) = getNavigationGrid()
        guard !grid.isEmpty else { return }

        if let (row, col) = findCurrentPosition(in: grid) {
            if col > 0 {
                highlightedItem = grid[row][col - 1]
            }
        } else {
            highlightedItem = getDefaultItem()
        }
    }

    private func navigateRight() {
        let (grid, _) = getNavigationGrid()
        guard !grid.isEmpty else { return }

        if let (row, col) = findCurrentPosition(in: grid) {
            let currentRow = grid[row]
            if col < currentRow.count - 1 {
                highlightedItem = currentRow[col + 1]
            }
        } else {
            highlightedItem = getDefaultItem()
        }
    }

    private func startMouseMovementMonitor() {
        // Remove existing monitors if any
        stopMouseMovementMonitor()

        // Global monitor for mouse movement outside the app
        mouseMovementMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.exitNavigationMode()
            }
        }

        // Local monitor for mouse movement inside the app (over the keyboard panel)
        localMouseMovementMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            DispatchQueue.main.async {
                self?.exitNavigationMode()
            }
            return event
        }
    }

    private func stopMouseMovementMonitor() {
        if let monitor = mouseMovementMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMovementMonitor = nil
        }
        if let monitor = localMouseMovementMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMovementMonitor = nil
        }
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

// MARK: - Array Chunking Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
