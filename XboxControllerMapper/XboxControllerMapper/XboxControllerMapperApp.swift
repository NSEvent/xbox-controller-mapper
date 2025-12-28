import SwiftUI
import GameController

/// Holds all app services as a shared singleton
@MainActor
final class ServiceContainer {
    let controllerService: ControllerService
    let profileManager: ProfileManager
    let appMonitor: AppMonitor
    let mappingEngine: MappingEngine

    init() {
        let controllerService = ControllerService()
        let profileManager = ProfileManager()
        let appMonitor = AppMonitor()

        self.controllerService = controllerService
        self.profileManager = profileManager
        self.appMonitor = appMonitor
        self.mappingEngine = MappingEngine(
            controllerService: controllerService,
            profileManager: profileManager,
            appMonitor: appMonitor
        )
    }
}

@main
struct XboxControllerMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Single container holding all services - using State since it's not ObservableObject
    @State private var services = ServiceContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(services.controllerService)
                .environmentObject(services.profileManager)
                .environmentObject(services.appMonitor)
                .environmentObject(services.mappingEngine)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra("Xbox Controller Mapper", systemImage: services.controllerService.isConnected ? "gamecontroller.fill" : "gamecontroller") {
            MenuBarView()
                .environmentObject(services.controllerService)
                .environmentObject(services.profileManager)
                .environmentObject(services.mappingEngine)
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
            print("Accessibility permissions granted - global input simulation enabled")
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
            Xbox Controller Mapper needs Accessibility permission to simulate keyboard and mouse input in other apps.

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
