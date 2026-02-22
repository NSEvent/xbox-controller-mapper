import Foundation
import IOKit.hid

/// Low-level HID monitor specifically to capture the Xbox Guide/Home button
/// which is often swallowed by the macOS GameController framework.
class XboxGuideMonitor {

    private var hidManager: IOHIDManager?
    private var callbackContext: UnsafeMutableRawPointer?
    private(set) var isStarted = false

    // Callback to main controller service
    // button state: true = pressed, false = released
    var onGuideButtonAction: ((Bool) -> Void)?

    /// Holds a weak monitor reference so callback dispatch remains safe
    /// even if HID callbacks race monitor teardown.
    private final class CallbackContext {
        weak var monitor: XboxGuideMonitor?

        init(monitor: XboxGuideMonitor) {
            self.monitor = monitor
        }
    }

    // MARK: - Static Callbacks

    private static let deviceMatchedCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let holder = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
        holder.monitor?.deviceMatched(device)
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let holder = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
        holder.monitor?.deviceRemoved(device)
    }

    private static let inputValueCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let holder = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
        holder.monitor?.handleInput(value)
    }

    // MARK: - Lifecycle

    init() {
        start()
    }

    deinit {
        stop()
    }

    func start() {
        guard !isStarted else { return }

        // Create an HID Manager
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let hidManager = hidManager else {
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

        // Register callbacks with retained context
        let retainedContext = Unmanaged.passRetained(CallbackContext(monitor: self)).toOpaque()
        callbackContext = retainedContext
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, Self.deviceMatchedCallback, retainedContext)
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, Self.deviceRemovedCallback, retainedContext)
        IOHIDManagerRegisterInputValueCallback(hidManager, Self.inputValueCallback, retainedContext)

        // Schedule with run loop
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // Open
        _ = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        isStarted = true
    }

    func stop() {
        guard isStarted || callbackContext != nil else { return }

        if let hidManager = hidManager {
            IOHIDManagerRegisterDeviceMatchingCallback(hidManager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(hidManager, nil, nil)
            IOHIDManagerRegisterInputValueCallback(hidManager, nil, nil)

            if isStarted {
                IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }

        if let callbackContext {
            Unmanaged<CallbackContext>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }
        isStarted = false
    }

    // MARK: - Handlers

    fileprivate func deviceMatched(_ device: IOHIDDevice) {
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
    }

    fileprivate func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Xbox Guide button is typically Button Usage 17 (0x11) on Button Page (0x09)
        // Some firmwares/drivers might map it differently, e.g. Usage 11 or 12.
        // We look for the Button usage page.
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
