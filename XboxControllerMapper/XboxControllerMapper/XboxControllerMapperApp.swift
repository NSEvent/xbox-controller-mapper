import SwiftUI
import GameController
import Combine

enum AppRuntime {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Screenshot capture mode, set via `--screenshot-variant <name>` by
    /// Scripts/capture-screenshots.sh. Valid names: dualsense, dualsense-edge,
    /// dualshock, xbox, xbox-elite, nintendo, steam, appletv. When set, hardware
    /// monitoring is disabled and the controller preview is forced to the given
    /// variant, so captures are deterministic regardless of paired hardware.
    static var screenshotVariant: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--screenshot-variant"),
              args.index(after: flagIndex) < args.endIndex else {
            return nil
        }
        return args[args.index(after: flagIndex)]
    }

    /// With `--screenshot-variant`, additionally runs a scripted input loop
    /// (sweeping sticks, tapping buttons) for GIF/video recordings. See
    /// Scripts/capture-demo-gifs.sh.
    static var screenshotAnimate: Bool {
        ProcessInfo.processInfo.arguments.contains("--screenshot-animate")
    }

    /// Per-variant zoom for the Buttons-tab preview in screenshot mode
    /// (`--screenshot-zoom 1.2`). Controllers with extra sections (Elite
    /// paddles, Steam grips) need less zoom than sparse layouts like Xbox.
    static var screenshotZoom: CGFloat? {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--screenshot-zoom"),
              args.index(after: flagIndex) < args.endIndex,
              let value = Double(args[args.index(after: flagIndex)]) else {
            return nil
        }
        return CGFloat(value)
    }
}

/// Holds all app services as a shared singleton
@MainActor
final class ServiceContainer {
    static let shared = ServiceContainer()

    let controllerService: ControllerService
    let profileManager: ProfileManager
    let appMonitor: AppMonitor
    let mappingEngine: MappingEngine
    let inputMonitor: InputMonitor
    let inputLogService: InputLogService
    let usageStatsService: UsageStatsService
    let batteryNotificationManager: BatteryNotificationManager
    let updateCheckService: UpdateCheckService

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Screenshot mode disables hardware monitoring so a live controller
        // can't override the forced preview variant mid-capture.
        let controllerService = ControllerService(
            enableHardwareMonitoring: AppRuntime.screenshotVariant == nil
        )
        let appMonitor = AppMonitor()
        let profileManager = ProfileManager(appMonitor: appMonitor)
        let inputMonitor = InputMonitor()
        let inputLogService = InputLogService()
        let usageStatsService = UsageStatsService()

        self.controllerService = controllerService
        self.profileManager = profileManager
        self.appMonitor = appMonitor
        self.inputMonitor = inputMonitor
        self.inputLogService = inputLogService
        self.usageStatsService = usageStatsService
        self.mappingEngine = MappingEngine(
            controllerService: controllerService,
            profileManager: profileManager,
            appMonitor: appMonitor,
            inputLogService: inputLogService,
            usageStatsService: usageStatsService
        )
        if !AppRuntime.isRunningTests {
            UniversalControlMouseRelay.shared.startListening(
                inputSimulator: self.mappingEngine.inputSimulator
            )
        }

        let batteryNotificationManager = BatteryNotificationManager()
        self.batteryNotificationManager = batteryNotificationManager
        if !AppRuntime.isRunningTests {
            batteryNotificationManager.startMonitoring(controllerService: controllerService)
        }

        let updateCheckService = UpdateCheckService()
        self.updateCheckService = updateCheckService
        // Skip in screenshot mode too — an update alert would land mid-capture.
        if !AppRuntime.isRunningTests, AppRuntime.screenshotVariant == nil {
            updateCheckService.checkForUpdates()
        }

        // Wire up on-screen keyboard quick texts from profile manager
        setupOnScreenKeyboardObserver(profileManager: profileManager)
        profileManager.setupControllerAutoSwitching(with: controllerService)

        // Auto-show stream overlay if it was previously enabled. Deferred:
        // creating the panel during App init (before NSApp finishes
        // launching) leaves it ordered out — orderFrontRegardless is a
        // no-op that early.
        if !AppRuntime.isRunningTests, StreamOverlayManager.isEnabled {
            let controllerService = controllerService
            let inputLogService = inputLogService
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                StreamOverlayManager.shared.show(
                    controllerService: controllerService,
                    inputLogService: inputLogService
                )
            }
        }
    }

    private func setupOnScreenKeyboardObserver(profileManager: ProfileManager) {
        // Initial update
        let settings = profileManager.onScreenKeyboardSettings
        OnScreenKeyboardManager.shared.setQuickTexts(
            settings.quickTexts,
            defaultTerminal: settings.defaultTerminalApp,
            typingDelay: settings.typingDelay,
            appBarItems: settings.appBarItems,
            websiteLinks: settings.websiteLinks,
            showExtendedFunctionKeys: settings.showExtendedFunctionKeys,
            activateAllWindows: settings.activateAllWindows
        )
        OnScreenKeyboardManager.shared.setToggleShortcut(
            keyCode: settings.toggleShortcutKeyCode,
            modifiers: settings.toggleShortcutModifiers
        )
        DirectoryNavigatorManager.shared.defaultTerminalApp = settings.defaultTerminalApp

        // Observe active profile changes (keyboard settings are per-profile)
        profileManager.$activeProfile
            .receive(on: DispatchQueue.main)
	    .sink { _ in
		let settings = profileManager.onScreenKeyboardSettings
                OnScreenKeyboardManager.shared.setQuickTexts(
                    settings.quickTexts,
                    defaultTerminal: settings.defaultTerminalApp,
                    typingDelay: settings.typingDelay,
                    appBarItems: settings.appBarItems,
                    websiteLinks: settings.websiteLinks,
                    showExtendedFunctionKeys: settings.showExtendedFunctionKeys,
                    activateAllWindows: settings.activateAllWindows
                )
                OnScreenKeyboardManager.shared.setToggleShortcut(
                    keyCode: settings.toggleShortcutKeyCode,
                    modifiers: settings.toggleShortcutModifiers
                )
                DirectoryNavigatorManager.shared.defaultTerminalApp = settings.defaultTerminalApp
            }
            .store(in: &cancellables)
    }
}

/// Menu bar label. SwiftUI's MenuBarExtra ignores complex view hierarchies in
/// the label slot — only a single Image renders reliably as a template icon.
/// We composite gamecontroller + lock into one NSImage when locked.
struct MenuBarLabel: View {
    @ObservedObject var controllerService: ControllerService
    @ObservedObject var mappingEngine: MappingEngine

    private var iconImage: NSImage? {
        let baseName = controllerService.isConnected ? "gamecontroller.fill" : "gamecontroller"
        guard let base = NSImage(systemSymbolName: baseName, accessibilityDescription: nil) else {
            return nil
        }
        if !mappingEngine.isLocked { return base }
        guard let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked") else {
            return base
        }
        return composite(base: base, overlay: lock)
    }

    /// Renders `base` and `overlay` (a smaller, centered lock) into a single
    /// non-template NSImage so the lock can be drawn in red while the
    /// gamecontroller follows the menu bar text color.
    private func composite(base: NSImage, overlay: NSImage) -> NSImage {
        let size = base.size
        let result = NSImage(size: size)
        result.lockFocus()
        // Tint the base gamecontroller with the system label color (auto-adapts
        // to light/dark menu bar) at 45% opacity.
        if let tintedBase = tinted(image: base, color: NSColor.labelColor) {
            tintedBase.draw(in: NSRect(origin: .zero, size: size),
                            from: .zero,
                            operation: .sourceOver,
                            fraction: 0.45)
        }
        let overlayScale: CGFloat = 0.65
        let overlaySize = NSSize(width: size.width * overlayScale,
                                 height: size.height * overlayScale)
        let overlayOrigin = NSPoint(x: (size.width - overlaySize.width) / 2,
                                    y: (size.height - overlaySize.height) / 2)
        if let tintedOverlay = tinted(image: overlay, color: NSColor.systemRed) {
            tintedOverlay.draw(in: NSRect(origin: overlayOrigin, size: overlaySize),
                               from: .zero,
                               operation: .sourceOver,
                               fraction: 1.0)
        }
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    /// Returns a copy of `image` tinted with `color` (preserves alpha).
    private func tinted(image: NSImage, color: NSColor) -> NSImage? {
        let copy = image.copy() as? NSImage ?? image
        copy.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: copy.size)
        rect.fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }

    var body: some View {
        if let icon = iconImage {
            Image(nsImage: icon)
        } else {
            Image(systemName: "gamecontroller")
        }
    }
}

/// Drives the app's `NSApplication.ActivationPolicy` so the dock icon presence
/// can follow window visibility when "Hide Dock Icon" is enabled.
///
/// Behavior:
/// - When `hideFromDock` UserDefault is **off**: the app is always `.regular`
///   (dock icon always visible — standard app behavior).
/// - When `hideFromDock` UserDefault is **on**: the app is `.regular` while a
///   user-facing window is visible, and `.accessory` when no such window is
///   visible. This matches the conventional macOS menu-bar-app pattern: opening
///   the main window temporarily promotes the app to the dock; closing it
///   returns to a quiet menu-bar-only presence.
///
/// We filter `NSApp.windows` to "user-facing app windows" — titled NSWindows
/// that aren't `NSPanel`. That deliberately excludes the MenuBarExtra popover
/// (an NSPanel) and system panels (alerts, color picker), which would
/// otherwise cause spurious dock-icon promotions.
@MainActor
final class DockVisibilityController {
    static let shared = DockVisibilityController()

    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var forceRegularUntil: Date?

    static let hideFromDockDefaultsKey = "hideFromDock"

    private var hideFromDock: Bool {
        UserDefaults.standard.bool(forKey: Self.hideFromDockDefaultsKey)
    }

    func start() {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default

        // didBecomeKey covers "the user just opened or focused a window" — the
        // common path that promotes the dock icon. NSWindow has no public
        // "didBecomeVisible" notification, but didChangeOcclusionState fires
        // when a window goes from hidden→visible (and vice versa), which
        // catches the cases didBecomeKey doesn't (e.g. window restored from
        // background without gaining focus). willClose / didMiniaturize /
        // didDeminiaturize round out the visibility-affecting events.
        let interestingNames: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]

        for name in interestingNames {
            // willClose fires *before* isVisible flips, so defer the recompute
            // briefly. Other notifications can update synchronously.
            let deferToNextTick = (name == NSWindow.willCloseNotification)
            observers.append(
                center.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    // Notifications delivered on .main queue are on the main
                    // thread; the addObserver closure isn't @MainActor-typed,
                    // so assert isolation explicitly.
                    MainActor.assumeIsolated {
                        guard let self,
                              let window = note.object as? NSWindow,
                              Self.isUserFacingAppWindow(window) else { return }
                        if deferToNextTick {
                            self.forceRegularUntil = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                self.updatePolicy()
                            }
                        } else {
                            self.updatePolicy()
                        }
                    }
                }
            )
        }

        updatePolicy()
    }

    /// Settings UI calls this after toggling the `hideFromDock` UserDefault so
    /// the policy applies immediately (we don't want to rely on KVO of a plain
    /// UserDefaults key).
    func preferenceChanged() {
        if hideFromDock {
            promoteForOpeningMainWindow()
        } else {
            forceRegularUntil = nil
            updatePolicy()
        }
    }

    /// Keeps the app in `.regular` long enough for SwiftUI to materialize or
    /// reactivate the main Window scene. Without this grace period, a menu-bar
    /// click can promote the app, observe "no visible main window" before
    /// `openWindow` completes, then immediately demote back to `.accessory`.
    func promoteForOpeningMainWindow() {
        let deadline = Date().addingTimeInterval(1.5)
        forceRegularUntil = deadline
        applyPolicy(.regular)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                if self?.forceRegularUntil == deadline {
                    self?.forceRegularUntil = nil
                }
                self?.updatePolicy()
            }
        }
    }

    /// Recomputes the activation policy based on the current preference and
    /// window state. Idempotent — safe to call repeatedly.
    func updatePolicy() {
        let target = Self.targetActivationPolicy(
            hideFromDock: hideFromDock,
            hasUserFacingWindow: anyUserFacingWindowVisible(),
            hasTemporaryRegularPromotion: hasTemporaryRegularPromotion()
        )
        applyPolicy(target)
    }

    private func applyPolicy(_ target: NSApplication.ActivationPolicy) {
        if NSApp.activationPolicy() != target {
            NSApp.setActivationPolicy(target)
        }
    }

    private func hasTemporaryRegularPromotion(now: Date = Date()) -> Bool {
        guard let forceRegularUntil else { return false }
        return forceRegularUntil > now
    }

    private func anyUserFacingWindowVisible() -> Bool {
        NSApp.windows.contains { window in
            Self.isUserFacingAppWindow(window) && window.isVisible && !window.isMiniaturized
        }
    }

    /// Filters `NSApp.windows` down to windows that represent the user actively
    /// using the app's UI. Excludes:
    /// - `NSPanel` instances (MenuBarExtra popover, alerts, color picker, etc.)
    /// - Untitled helper windows (tooltips, hidden hosting windows)
    ///
    /// Internal so tests can verify the filter without going through `NSApp`.
    static func isUserFacingAppWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel { return false }
        guard window.styleMask.contains(.titled) else { return false }
        return true
    }

    static func targetActivationPolicy(
        hideFromDock: Bool,
        hasUserFacingWindow: Bool,
        hasTemporaryRegularPromotion: Bool
    ) -> NSApplication.ActivationPolicy {
        if !hideFromDock || hasUserFacingWindow || hasTemporaryRegularPromotion {
            return .regular
        }
        return .accessory
    }
}

@main
struct XboxControllerMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        // Single-window scene (prevents Cmd+N from opening duplicates)
        Window("ControllerKeys", id: "main") {
            ContentView()
                .environmentObject(ServiceContainer.shared.controllerService)
                .environmentObject(ServiceContainer.shared.profileManager)
                .environmentObject(ServiceContainer.shared.appMonitor)
                .environmentObject(ServiceContainer.shared.mappingEngine)
                .environmentObject(ServiceContainer.shared.inputMonitor)
                .environmentObject(ServiceContainer.shared.inputLogService)
                .environmentObject(ServiceContainer.shared.usageStatsService)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(ServiceContainer.shared.controllerService)
                .environmentObject(ServiceContainer.shared.profileManager)
                .environmentObject(ServiceContainer.shared.mappingEngine)
                .environmentObject(ServiceContainer.shared.inputMonitor)
                .environmentObject(ServiceContainer.shared.inputLogService)
        } label: {
            MenuBarLabel(
                controllerService: ServiceContainer.shared.controllerService,
                mappingEngine: ServiceContainer.shared.mappingEngine
            )
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    /// Activity token to prevent App Nap from suspending the app
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppRuntime.isRunningTests else { return }

		// Start controller monitoring immediately, even when SwiftUI defers scene content.
		_ = ServiceContainer.shared

        // Disable App Nap to ensure controller events are received in background
        disableAppNap()

        // Request Accessibility permissions if not granted
        requestAccessibilityPermissions()

        // Wire up dynamic dock-icon visibility. When `hideFromDock` is enabled,
        // the activation policy follows window visibility (dock icon only appears
        // while the main window is open). When disabled, the app is always .regular.
        DockVisibilityController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !AppRuntime.isRunningTests else { return }

        ServiceContainer.shared.controllerService.cleanup()
        ServiceContainer.shared.usageStatsService.endSession()
        ServiceContainer.shared.profileManager.flushPendingSaves()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in menu bar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockVisibilityController.shared.promoteForOpeningMainWindow()

        if !flag {
            sender.windows
                .first(where: DockVisibilityController.isUserFacingAppWindow)?
                .makeKeyAndOrderFront(nil)
        }

        return true
    }

    private func disableAppNap() {
        // Begin an activity that prevents App Nap from suspending the app
        // This is critical for receiving controller input when the app is in the background
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Processing controller input for global keyboard/mouse mapping"
        )
    }

    private func requestAccessibilityPermissions() {
        // First check if we already have permissions
        if AXIsProcessTrusted() {
            return
        }

        // Try to trigger the system prompt (this also adds the app to the list)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !trusted {
            // System prompt may not appear on newer macOS or after rebuilds
            // Show our own alert and open System Settings directly
            DispatchQueue.main.async {
                self.showAccessibilityAlert()
            }
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            ControllerKeys needs Accessibility permission to simulate keyboard and mouse input in other apps.

            1. Click "Open System Settings"
            2. Click the "+" button at the bottom of the list
            3. Navigate to the app and add it
            4. Toggle the switch ON

            The app is located at:
            \(Bundle.main.bundlePath)
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            // Open System Settings to Accessibility
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)

            // Also reveal the app in Finder so user can drag it
            NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "")
        }
    }

    /// Check if accessibility is currently enabled (can be called anytime)
    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }
}
