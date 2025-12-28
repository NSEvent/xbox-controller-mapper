import SwiftUI
import GameController

@main
struct XboxControllerMapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controllerService = ControllerService()
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var appMonitor = AppMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controllerService)
                .environmentObject(profileManager)
                .environmentObject(appMonitor)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra("Xbox Controller Mapper", systemImage: controllerService.isConnected ? "gamecontroller.fill" : "gamecontroller") {
            MenuBarView()
                .environmentObject(controllerService)
                .environmentObject(profileManager)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request Accessibility permissions if not granted
        requestAccessibilityPermissions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep running in menu bar
    }

    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)

        if !trusted {
            print("Accessibility permissions not granted. Some features may not work.")
        }
    }
}
