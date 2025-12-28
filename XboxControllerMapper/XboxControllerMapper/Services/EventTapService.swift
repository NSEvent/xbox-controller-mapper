import Foundation
import Cocoa
import Combine

class EventTapService {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Publisher that emits when the guide button is detected
    let onGuideButtonPressed = PassthroughSubject<Void, Never>()
    
    init() {
        setupEventTap()
    }
    
    private func setupEventTap() {
        print("Setting up Event Tap for Xbox Guide Button...")
        
        // kCGEventSystemDefined is 14
        let systemDefinedEventType = CGEventType(rawValue: 14)!
        let eventMask = (1 << systemDefinedEventType.rawValue) | (1 << CGEventType.keyDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if let observer = refcon {
                    let service = Unmanaged<EventTapService>.fromOpaque(observer).takeUnretainedValue()
                    return service.handleEvent(proxy: proxy, type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap. Check permissions.")
            return
        }
        
        self.eventTap = eventTap
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
        self.runLoopSource = runLoopSource
        
        CGEvent.tapEnable(tap: eventTap, enable: true)
        print("Event Tap created and enabled.")
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        
        // kCGEventSystemDefined is 14
        if type.rawValue == 14 {
            // This is where we look for the guide button.
            // The NSEvent subtype for system defined events is often 7 for system keys.
            // Data1 and Data2 contain specific info.
            
            if let nsEvent = NSEvent(cgEvent: event) {
                if nsEvent.subtype.rawValue == 7 { // System Defined
                    let data1 = nsEvent.data1
                    let data2 = nsEvent.data2
                    
                    // Known signature for some controllers or "Launchpad" key
                    // For debugging: verify this print appears when pressing the button.
                    print("SystemEvent: subtype=\(nsEvent.subtype.rawValue), data1=\(data1), data2=\(data2)")
                    
                    // Match Xbox Guide Button (Launchpad mapping for some drivers)
                    // Common usage: data1 = 0xAF0000 or similar for Launchpad
                    // We'll filter based on user logs later
                }
            }
        }
        
        // Pass through everything else
        return Unmanaged.passUnretained(event)
    }
}
