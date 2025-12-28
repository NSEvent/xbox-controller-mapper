import Cocoa
import Combine

/// Monitors global keyboard and mouse events
class InputMonitor: ObservableObject {
    @Published var lastEvent: NSEvent?
    
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Automatically start monitoring if permissions allow
        // DISABLED auto-start to debug blocking issue
        if AXIsProcessTrusted() {
            startMonitoring()
        }
    }
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        // 1. Check Permissions
        guard AXIsProcessTrusted() else {
            print("Accessibility permissions not granted. Cannot monitor events.")
            return
        }
        
        // 2. Stop existing monitors to avoid duplicates
        stopMonitoring()
        
        // 3. Register Global Monitor (Background)
        // We monitor flagsChanged (modifiers) and keyDown
        // Removed .otherMouseDown to prevent potential interference
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
        }
        
        // 4. Register Local Monitor (Foreground)
        // Global monitor doesn't fire when WE are the focused app.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { [weak self] event in
            self?.handleEvent(event)
            return event // Return the event so it propagates normally
        }
        
        print("InputMonitor started.")
    }
    
    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        print("InputMonitor stopped.")
    }
    
    private func handleEvent(_ event: NSEvent) {
        // UI updates should happen on main thread
        DispatchQueue.main.async {
            self.lastEvent = event
        }
        
        // Example logic
        if event.type == .keyDown {
            // print("InputMonitor: Key pressed code: \(event.keyCode)")
        } else if event.type == .flagsChanged {
             // print("InputMonitor: Modifiers changed: \(event.modifierFlags)")
        }
    }
}
