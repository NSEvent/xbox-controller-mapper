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

        // Check required permissions
        checkPermissions()
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

    private func checkPermissions() {
        // 1. Check Accessibility (for simulating input)
        // 2. Check Input Monitoring (for reading controller in background)
        
        if !checkAccessibilityPermissions() {
            return // Will show alert
        }
        
        checkInputMonitoringPermissions()
    }

    private func checkAccessibilityPermissions() -> Bool {
        if AXIsProcessTrusted() {
            print("Accessibility permissions granted")
            return true
        }

        // Try to trigger system prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !trusted {
            DispatchQueue.main.async {
                self.showAccessibilityAlert()
            }
        }
        
        return trusted
    }

    private func checkInputMonitoringPermissions() {
        // There isn't a direct API to check "Input Monitoring" status like AXIsProcessTrusted.
        // The robust way is to try creating a passive temporary event tap.
        // If it fails (returns nil), we likely lack permission.
        
        // Try to create a tap for a common event like mouseMoved.
        // We use .listenOnly so we don't actually interfere with anything.
        let eventMask = (1 << CGEventType.mouseMoved.rawValue)
        guard let _ = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, _, _ in return nil },
            userInfo: nil
        ) else {
            print("Input Monitoring check failed - permission likely missing")
            DispatchQueue.main.async {
                self.showInputMonitoringAlert()
            }
            return
        }
        
        // If we got here, we have permission. Release the tap.
        // Note: CFMachPort or CFRunLoopSource might be created, but just letting it go out of scope 
        // without adding to a runloop is usually enough for a quick check,
        // but explicitly CFRelease-ing if needed is good practice if we were using CoreFoundation types directly.
        // Swift handles ARC for 'tap' (CFMachPort) approx correctly here.
        print("Input Monitoring permissions appear to be granted")
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Xbox Controller Mapper needs Accessibility permission to simulate keyboard and mouse input.

            1. Click "Open System Settings"
            2. Enable "Xbox Controller Mapper" in the list

            The app is located at:
            \(Bundle.main.bundlePath)
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            // macOS 13+ link
            let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            // Also reveal the app in Finder
            NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "")
        }
    }

    private func showInputMonitoringAlert() {
        let alert = NSAlert()
        alert.messageText = "Input Monitoring Permission Required"
        alert.informativeText = """
            Xbox Controller Mapper needs Input Monitoring permission to detect controller buttons when the app is in the background.

            1. Click "Open System Settings"
            2. Click the "+" button if the app isn't listed
            3. Enable "Xbox Controller Mapper"
            4. Restart the app if prompted

            The app is located at:
            \(Bundle.main.bundlePath)
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            // Direct link to Input Monitoring
            let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            
             // Also reveal the app in Finder so user can drag it easily if needed
            NSWorkspace.shared.selectFile(Bundle.main.bundlePath, inFileViewerRootedAtPath: "")
        }
    }
    
    /// Check if accessibility is currently enabled (can be called anytime)
    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }
}
