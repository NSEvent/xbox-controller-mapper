import Cocoa
import Combine

/// Monitors keyboard and mouse events for the app
class InputMonitor: ObservableObject {
    @Published var lastEvent: NSEvent?

    private var localMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init() {
        if AXIsProcessTrusted() {
            startMonitoring()
        }
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard AXIsProcessTrusted() else {
            return
        }

        stopMonitoring()

        // Local monitor for foreground events only
        // Background controller events are handled by GCController.shouldMonitorBackgroundEvents
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }

    func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) {
        DispatchQueue.main.async {
            self.lastEvent = event
        }
    }
}
