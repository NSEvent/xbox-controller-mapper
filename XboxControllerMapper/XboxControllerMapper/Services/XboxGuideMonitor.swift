import Foundation
import IOKit.hid

/// Low-level HID monitor specifically to capture the Xbox Guide/Home button
/// which is often swallowed by the macOS GameController framework.
class XboxGuideMonitor {
private var hidManager: IOHIDManager?

// Callback to main controller service
// button state: true = pressed, false = released
var onGuideButtonAction: ((Bool) -> Void)?

init() {
    setupHIDManager()
}

deinit {
    stopHIDManager()
}

private func setupHIDManager() {
    // Create an HID Manager
    hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    guard let hidManager = hidManager else {
        print("❌ HID: Failed to create IOHIDManager")
        return
    }

    // Match generic gamepads and joysticks
    let gamepadMatching = [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad
    ] as CFDictionary
    
    let joystickMatching = [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick
    ] as CFDictionary

    let criteria = [gamepadMatching, joystickMatching] as CFArray
    IOHIDManagerSetDeviceMatchingMultiple(hidManager, criteria)

    // Register callbacks
    let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    IOHIDManagerRegisterDeviceMatchingCallback(hidManager, HandleDeviceMatched, context)
    IOHIDManagerRegisterDeviceRemovalCallback(hidManager, HandleDeviceRemoved, context)
    IOHIDManagerRegisterInputValueCallback(hidManager, HandleInputValue, context)

    // Schedule with run loop
    IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

    // Open
    let status = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
    if status != kIOReturnSuccess {
        print("❌ HID: Failed to open IOHIDManager: \(status)")
    } else {
        print("✅ HID: Monitor started for Xbox Guide button")
    }
}

private func stopHIDManager() {
    if let hidManager = hidManager {
        IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
}

// MARK: - Handlers

fileprivate func deviceMatched(_ device: IOHIDDevice) {
    let name = getDeviceName(device)
    print("🎮 HID: Device matched: \(name)")
}

fileprivate func deviceRemoved(_ device: IOHIDDevice) {
    print("🎮 HID: Device removed")
}

fileprivate func handleInput(_ value: IOHIDValue) {
    let element = IOHIDValueGetElement(value)
    let usagePage = IOHIDElementGetUsagePage(element)
    let usage = IOHIDElementGetUsage(element)
    let intValue = IOHIDValueGetIntegerValue(value)
    
    // Xbox Guide button is typically Button Usage 17 (0x11) on Button Page (0x09)
    // Some firmwares/drivers might map it differently, e.g. Usage 11 or 12.
    // We look for the But ton usage page.
    if usagePage == kHIDPage_Button {
        // Usage 17 is standard for Xbox One/Series Guide button over USB on macOS
        // Usage 11 or 12 is the select and start button
        // Usage 13 is for the Xbox Series X/S controller over Bluetooth on macOS
        if usage == 17 || usage == 13 {
            let isPressed = intValue != 0
            DispatchQueue.main.async { [weak self] in
                self?.onGuideButtonAction?(isPressed)
            }
        }
    }
}

private func getDeviceName(_ device: IOHIDDevice) -> String {
    if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
        return name
    }
    return "Unknown HID Device"
}
}

// MARK: - C Callbacks

private func HandleDeviceMatched(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
guard let context = context else { return }
let monitor = Unmanaged<XboxGuideMonitor>.fromOpaque(context).takeUnretainedValue()
monitor.deviceMatched(device)
}

private func HandleDeviceRemoved(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
guard let context = context else { return }
let monitor = Unmanaged<XboxGuideMonitor>.fromOpaque(context).takeUnretainedValue()
monitor.deviceRemoved(device)
}

private func HandleInputValue(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
guard let context = context else { return }
let monitor = Unmanaged<XboxGuideMonitor>.fromOpaque(context).takeUnretainedValue()
monitor.handleInput(value)
}
