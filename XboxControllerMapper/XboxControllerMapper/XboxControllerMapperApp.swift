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

    /// Show the stream overlay panel in screenshot mode regardless of the
    /// user's preference (`--screenshot-overlay`). Used by the capture
    /// scripts so they don't have to toggle persistent prefs.
    static var screenshotShowOverlay: Bool {
        ProcessInfo.processInfo.arguments.contains("--screenshot-overlay")
    }

    /// Fixed window frames for screenshot mode, in top-left screen
    /// coordinates. The capture scripts rely on these exact frames, and the
    /// app placing its own windows avoids any dependence on the
    /// Accessibility API (which can wedge under heavy automation).
    static let screenshotMainWindowRect = CGRect(x: 100, y: 100, width: 1600, height: 1000)
    static let screenshotOverlayOrigin = CGPoint(x: 115, y: 640)

    /// Convert a top-left-origin screen rect to an AppKit (bottom-left
    /// origin) frame on the main screen.
    static func appKitFrame(topLeftRect rect: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first else { return rect }
        return CGRect(
            x: screen.frame.minX + rect.minX,
            y: screen.frame.maxY - rect.minY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// In screenshot mode, pin the main window to the fixed capture frame.
    @MainActor
    static func positionMainWindowForScreenshots() {
        guard screenshotVariant != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let window = NSApp.windows.first(where: {
                $0.frame.width > 400 && !($0 is NSPanel)
            }) else { return }
            window.setFrame(appKitFrame(topLeftRect: screenshotMainWindowRect), display: true)
        }
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
        // The cross-Mac relay listener publishes a Bonjour service, which
        // triggers the Local Network prompt. Only start it at launch if the user
        // has actually set up the relay — otherwise the prompt is deferred to
        // the sync button in Settings (see SettingsSheet.startRelayPairing), so a
        // user who never uses the feature never sees it.
        if !AppRuntime.isRunningTests, UniversalControlMouseRelay.shared.hasConfiguredRelay {
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

        // Trial enforcement: keep mapping off once the 14-day trial expires
        // (and no license), even when no window is open. Skipped in screenshot
        // mode so captures aren't affected by trial state.
        if !AppRuntime.isRunningTests, AppRuntime.screenshotVariant == nil {
            let engine = self.mappingEngine
            Task { @MainActor in
                LicenseManager.shared.enforce { engine.isEnabled = false }
            }

            // Start Sparkle's auto-update lifecycle (background checks + the
            // "Check for Updates" command). Skipped above for tests/screenshots.
            Task { @MainActor in
                UpdaterManager.shared.start()
            }

            // Anonymous, opt-out usage ping (active installs, version adoption,
            // trial → license conversion) now that downloads are free via
            // GitHub/Homebrew rather than Gumroad.
            Task { @MainActor in
                TelemetryService.shared.appLaunched(status: LicenseManager.shared.telemetryStatus)
            }
        }

        // Wire up on-screen keyboard quick texts from profile manager
        setupOnScreenKeyboardObserver(profileManager: profileManager)
        profileManager.setupControllerAutoSwitching(with: controllerService)

        // Auto-show stream overlay if it was previously enabled (or forced
        // by --screenshot-overlay; screenshot mode otherwise ignores the
        // pref so captures are deterministic). Deferred: creating the panel
        // during App init (before NSApp finishes launching) leaves it
        // ordered out — orderFrontRegardless is a no-op that early.
        let showOverlay = AppRuntime.screenshotVariant == nil
            ? StreamOverlayManager.isEnabled
            : AppRuntime.screenshotShowOverlay
        if !AppRuntime.isRunningTests, showOverlay {
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

/// Help-menu item that opens the standalone Connection Guides window. Kept as
/// its own `View` so it can read `@Environment(\.openWindow)` — that value isn't
/// available directly inside the `.commands` builder.
private struct ConnectionGuidesMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Controller Connection Guides") {
            openWindow(id: "connection-guides")
        }
    }
}

@main
struct XboxControllerMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	var body: some Scene {
		// Single-window scene (prevents Cmd+N from opening duplicates)
		Window("ControllerKeys", id: "main") {
			if AppRuntime.isRunningTests {
				EmptyView()
			} else {
				ContentView()
					.onAppear { AppRuntime.positionMainWindowForScreenshots() }
					.environmentObject(ServiceContainer.shared.controllerService)
					.environmentObject(ServiceContainer.shared.profileManager)
					.environmentObject(ServiceContainer.shared.appMonitor)
					.environmentObject(ServiceContainer.shared.mappingEngine)
					.environmentObject(ServiceContainer.shared.inputMonitor)
					.environmentObject(ServiceContainer.shared.inputLogService)
					.environmentObject(ServiceContainer.shared.usageStatsService)
			}
		}
		.windowResizability(.contentSize)
		.commands {
			CommandGroup(after: .help) {
				ConnectionGuidesMenuItem()
				Button("Controller Support Dump...") {
					ControllerSupportDumpService.runInteractiveDump()
				}
			}
		}

		Window("Controller Connection Guides", id: "connection-guides") {
			if AppRuntime.isRunningTests {
				EmptyView()
			} else {
				ConnectionGuidesView()
			}
		}
		// The view has a fixed width and content-driven height, so the window
		// sizes itself to each guide (and the chooser) and re-sizes as the user
		// navigates between controllers - no scrolling, no manual resize.
		.windowResizability(.contentSize)

		MenuBarExtra {
			if AppRuntime.isRunningTests {
				EmptyView()
			} else {
				MenuBarView()
					.environmentObject(ServiceContainer.shared.controllerService)
					.environmentObject(ServiceContainer.shared.profileManager)
					.environmentObject(ServiceContainer.shared.mappingEngine)
					.environmentObject(ServiceContainer.shared.inputMonitor)
					.environmentObject(ServiceContainer.shared.inputLogService)
			}
		} label: {
			if AppRuntime.isRunningTests {
				Image(systemName: "gamecontroller")
			} else {
				MenuBarLabel(
					controllerService: ServiceContainer.shared.controllerService,
					mappingEngine: ServiceContainer.shared.mappingEngine
				)
			}
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

        // Permissions are no longer requested in a launch-time prompt-wall.
        // The first-run onboarding wizard (ContentView) drives them one at a
        // time. Here we just wire the "permission was just granted" hooks so a
        // grant re-activates the dependent services live, without a relaunch.
        wirePermissionHooks()

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

    /// Connects the central `PermissionsManager` to the services that depend on
    /// each permission, so granting one during onboarding (or later) takes effect
    /// live. `onAccessibilityGranted` restarts the local event monitor (the
    /// `InputSimulator` re-polls on its own); `onInputMonitoringGranted` opens
    /// the deferred IOHID monitors; `requestBluetoothAction` starts the battery
    /// monitor (whose `CBCentralManager` is what surfaces the Bluetooth prompt).
    private func wirePermissionHooks() {
        let permissions = PermissionsManager.shared
        permissions.onAccessibilityGranted = {
            ServiceContainer.shared.inputMonitor.startMonitoring()
        }
        permissions.onInputMonitoringGranted = {
            ServiceContainer.shared.controllerService.startInputMonitoringHID()
        }
        permissions.requestBluetoothAction = {
            ServiceContainer.shared.controllerService.startBluetoothBattery()
        }
    }

    /// Check if accessibility is currently enabled (can be called anytime)
    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }
}
