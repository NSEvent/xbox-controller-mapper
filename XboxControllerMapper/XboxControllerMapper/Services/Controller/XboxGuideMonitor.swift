import Foundation
import IOKit.hid

/// Low-level HID monitor specifically to capture the Xbox Guide/Home button
/// which is often swallowed by the macOS GameController framework.
class XboxGuideMonitor {

    private var hidManager: IOHIDManager?
    private var callbackContext: UnsafeMutableRawPointer?
    private(set) var isStarted = false

    /// Opaque pointers to devices identified as Xbox Elite Series 2 (tracked to avoid
    /// misinterpreting paddle buttons as the Guide button — see handleInput for details).
    private var eliteDevicePointers = Set<UnsafeMutableRawPointer>()

    /// Known Xbox Elite Series 2 product IDs (Microsoft VID 0x045E).
    private static let eliteSeries2PIDs: Set<Int> = [
        0x0B00,  // Elite 2
        0x0B02,  // Elite 2 Core
        0x0B05,  // Elite 2 (USB)
        0x0B22,  // Elite 2 (Bluetooth)
    ]

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
        if Self.isEliteController(device) {
            eliteDevicePointers.insert(Unmanaged.passUnretained(device).toOpaque())
        }
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        eliteDevicePointers.remove(Unmanaged.passUnretained(device).toOpaque())
    }

    fileprivate func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Consumer Page: AC Home (0x0223) is used by Xbox controllers over Bluetooth
        // to report the Guide button (including Xbox Elite Series 2).
        if usagePage == kHIDPage_Consumer && usage == 0x0223 {
            let isPressed = intValue != 0
            DispatchQueue.main.async { [weak self] in
                self?.onGuideButtonAction?(isPressed)
            }
            return
        }

        if usagePage == kHIDPage_Button {
            // Usage 17 is standard for Xbox One/Series Guide button over USB on macOS
            if usage == 17 {
                let isPressed = intValue != 0
                DispatchQueue.main.async { [weak self] in
                    self?.onGuideButtonAction?(isPressed)
                }
                return
            }

            // Usage 13 is the Guide button for standard Xbox Series X/S controllers
            // over Bluetooth on macOS. However, on the Xbox Elite Series 2, usage 13
            // is a paddle button (P2/P3), NOT the Guide button — the Elite 2 reports
            // Guide via Consumer Page AC Home instead.
            if usage == 13 {
                let device = IOHIDElementGetDevice(element)
                let devicePtr = Unmanaged.passUnretained(device).toOpaque()
                guard !eliteDevicePointers.contains(devicePtr) else { return }
                let isPressed = intValue != 0
                DispatchQueue.main.async { [weak self] in
                    self?.onGuideButtonAction?(isPressed)
                }
            }
        }
    }

    private static func isEliteController(_ device: IOHIDDevice) -> Bool {
        guard let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int,
              vid == 0x045E,
              let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int else {
            return false
        }
        return eliteSeries2PIDs.contains(pid)
    }

    private func getDeviceName(_ device: IOHIDDevice) -> String {
        if let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String {
            return name
        }
        return "Unknown HID Device"
    }
}
