import SwiftUI
import GameController
import Combine

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

    private var cancellables = Set<AnyCancellable>()

    init() {
        let controllerService = ControllerService()
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

        let batteryNotificationManager = BatteryNotificationManager()
        self.batteryNotificationManager = batteryNotificationManager
        batteryNotificationManager.startMonitoring(controllerService: controllerService)

        // Wire up on-screen keyboard quick texts from profile manager
        setupOnScreenKeyboardObserver(profileManager: profileManager)

        // Auto-show stream overlay if it was previously enabled
        if StreamOverlayManager.isEnabled {
            StreamOverlayManager.shared.show(
                controllerService: controllerService,
                inputLogService: inputLogService
            )
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
            .sink { profile in
                let settings = profile?.onScreenKeyboardSettings ?? OnScreenKeyboardSettings()
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

        MenuBarExtra("ControllerKeys", systemImage: ServiceContainer.shared.controllerService.isConnected ? "gamecontroller.fill" : "gamecontroller") {
            MenuBarView()
                .environmentObject(ServiceContainer.shared.controllerService)
                .environmentObject(ServiceContainer.shared.profileManager)
                .environmentObject(ServiceContainer.shared.mappingEngine)
                .environmentObject(ServiceContainer.shared.inputMonitor)
                .environmentObject(ServiceContainer.shared.inputLogService)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    /// Activity token to prevent App Nap from suspending the app
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable App Nap to ensure controller events are received in background
        disableAppNap()

        // Request Accessibility permissions if not granted
        requestAccessibilityPermissions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ServiceContainer.shared.usageStatsService.endSession()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in menu bar
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
