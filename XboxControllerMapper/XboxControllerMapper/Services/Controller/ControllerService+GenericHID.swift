import Foundation
import IOKit
import IOKit.hid

// MARK: - Generic HID Controller Fallback

@MainActor
extension ControllerService {

    func setupGenericHIDMonitoring() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        genericHIDManager = manager

        let gamepadMatching = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad
        ] as CFDictionary

        let joystickMatching = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick
        ] as CFDictionary

        let criteria = [gamepadMatching, joystickMatching] as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, criteria)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, genericHIDDeviceMatched, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, genericHIDDeviceRemoved, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func cleanupGenericHIDMonitoring() {
        genericHIDFallbackTimer?.cancel()
        genericHIDFallbackTimer = nil
        genericHIDController?.stop()
        genericHIDController = nil
        if let manager = genericHIDManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
        genericHIDManager = nil
    }

    func genericDeviceAppeared(_ device: IOHIDDevice) {
        // Skip if we already have a connected controller (GameController or generic)
        guard !isConnected else { return }

        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let version = IOHIDDeviceGetProperty(device, kIOHIDVersionNumberKey as CFString) as? Int ?? 0
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String

        // Wait 1 second to give GameController framework priority
        genericHIDFallbackTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            self?.attemptGenericFallback(device: device, vendorID: vendorID,
                                         productID: productID, version: version,
                                         transport: transport)
        }
        genericHIDFallbackTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timer)
    }

    func attemptGenericFallback(device: IOHIDDevice, vendorID: Int, productID: Int,
                                         version: Int, transport: String?) {
        // Don't activate if GameController framework connected in the meantime
        guard !isConnected else { return }

        guard let mapping = GameControllerDatabase.shared.lookup(
            vendorID: vendorID, productID: productID,
            version: version, transport: transport
        ) else {
            #if DEBUG
            let guid = GameControllerDatabase.constructGUID(vendorID: vendorID, productID: productID,
                                                             version: version, transport: transport)
            print("[GenericHID] No mapping found for GUID: \(guid) (vendor=0x\(String(vendorID, radix: 16)), product=0x\(String(productID, radix: 16)))")
            #endif
            return
        }

        guard let controller = GenericHIDController(device: device, mapping: mapping) else {
            #if DEBUG
            print("[GenericHID] Failed to initialize controller for: \(mapping.name)")
            #endif
            return
        }

        // Wire callbacks through existing input handling
        controller.onButtonAction = { [weak self] button, pressed in
            self?.controllerQueue.async {
                self?.handleButton(button, pressed: pressed)
            }
        }
        controller.onLeftStickMoved = { [weak self] x, y in
            self?.updateLeftStick(x: x, y: y)
        }
        controller.onRightStickMoved = { [weak self] x, y in
            self?.updateRightStick(x: x, y: y)
        }
        controller.onLeftTriggerChanged = { [weak self] value, pressed in
            self?.updateLeftTrigger(value, pressed: pressed)
        }
        controller.onRightTriggerChanged = { [weak self] value, pressed in
            self?.updateRightTrigger(value, pressed: pressed)
        }

        controller.start()
        genericHIDController = controller
        isConnected = true
        isGenericController = true
        controllerName = mapping.name
        startDisplayUpdateTimer()

        #if DEBUG
        print("[GenericHID] Connected: \(mapping.name)")
        #endif
    }

    func genericDeviceRemoved(_ device: IOHIDDevice) {
        // Only handle if this is our active generic controller's device
        guard let controller = genericHIDController, controller.device == device else { return }
        controller.stop()
        genericHIDController = nil
        controllerDisconnected()
    }
}

// MARK: - Generic HID C Callbacks

private nonisolated func genericHIDDeviceMatched(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context = context else { return }
    let service = Unmanaged<ControllerService>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        service.genericDeviceAppeared(device)
    }
}

private nonisolated func genericHIDDeviceRemoved(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context = context else { return }
    let service = Unmanaged<ControllerService>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async {
        service.genericDeviceRemoved(device)
    }
}
