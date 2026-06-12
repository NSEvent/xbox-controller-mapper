import Foundation
import IOKit
import IOKit.hid

// MARK: - Generic HID Controller Fallback

/// Weak callback context for generic HID device matching/removal callbacks.
/// Prevents use-after-free when ControllerService is deallocated while a HID
/// callback fires on the run loop.
fileprivate final class GenericHIDCallbackContext {
    weak var service: ControllerService?
    init(service: ControllerService) { self.service = service }
}

private let genericHIDSetupQueue = DispatchQueue(label: "com.controllerkeys.generic-hid.setup", qos: .utility)

@MainActor
extension ControllerService {

    func setupGenericHIDMonitoring() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        genericHIDManager = manager

        let ctx = GenericHIDCallbackContext(service: self)
        let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
        genericHIDCallbackContext = retainedContext
        let context = UnsafeMutableRawPointer(retainedContext)

        genericHIDSetupQueue.async {
            let excludedVendors: Set<Int> = [
                0x045E, // Xbox raw Guide/Elite path
                0x054C, // PlayStation raw PS button path
                0x057E, // Nintendo raw Home button path
                SteamControllerHIDParser.valveVendorID,
            ]
	    let knownMappingCriteria = GameControllerDatabase.shared
                .knownVendorProductPairs(excludingVendors: excludedVendors)
                .map { pair in
                    [
                        kIOHIDVendorIDKey as String: pair.vendorID,
                        kIOHIDProductIDKey as String: pair.productID,
                    ] as CFDictionary
		}
	    let standardControllerCriteria = [
		[
		    kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
		    kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Joystick,
		],
		[
		    kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
		    kIOHIDDeviceUsageKey as String: kHIDUsage_GD_GamePad,
		],
		[
		    kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
		    kIOHIDDeviceUsageKey as String: kHIDUsage_GD_MultiAxisController,
		],
	    ].map { $0 as CFDictionary }
	    let bluetoothLECriteria = [
		[kIOHIDTransportKey as String: "BluetoothLowEnergy"],
		[kIOHIDTransportKey as String: "Bluetooth Low Energy"],
	    ].map { $0 as CFDictionary }
	    let criteria = (
		knownMappingCriteria +
		standardControllerCriteria +
		bluetoothLECriteria
	    ) as CFArray

            guard CFArrayGetCount(criteria) > 0 else { return }
            IOHIDManagerSetDeviceMatchingMultiple(manager, criteria)

            IOHIDManagerRegisterDeviceMatchingCallback(manager, genericHIDDeviceMatched, context)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, genericHIDDeviceRemoved, context)

            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    func cleanupGenericHIDMonitoring() {
        genericHIDFallbackTimer?.cancel()
        genericHIDFallbackTimer = nil
        genericHIDPendingFallbackDevice = nil
        genericHIDController?.stop()
        genericHIDController = nil

        let manager = genericHIDManager
        let context = genericHIDCallbackContext
        genericHIDManager = nil
        genericHIDCallbackContext = nil

        // Tear down on the same serial queue used by setup so cleanup can never
        // overtake an in-flight registration (which would unregister/release a
        // context IOKit is about to retain). Order: unregister → unschedule → close.
        genericHIDSetupQueue.async {
            if let manager {
                IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
                IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
                IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            if let context {
                // Release on the main queue: callbacks fire on the main run loop,
                // so any callback already executing when we unscheduled has
                // finished by the time this block runs.
                DispatchQueue.main.async {
                    Unmanaged<GenericHIDCallbackContext>.fromOpaque(context).release()
                }
            }
        }
    }

    func genericDeviceAppeared(_ device: IOHIDDevice) {
        // Skip if we already have a connected controller (GameController or generic)
        guard !isConnected else { return }

        let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let version = IOHIDDeviceGetProperty(device, kIOHIDVersionNumberKey as CFString) as? Int ?? 0
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
		let hasKnownMapping = GameControllerDatabase.shared.hasKnownVendorProduct(
		    vendorID: vendorID,
		    productID: productID
		)
		let canUseKnownMapping = hasKnownMapping && GenericHIDController.canUseKnownMapping(from: device)
		guard canUseKnownMapping || GenericHIDController.canInferMapping(from: device) else { return }

        // Wait 1 second to give GameController framework priority
        genericHIDFallbackTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            self?.attemptGenericFallback(device: device, vendorID: vendorID,
                                         productID: productID, version: version,
                                         transport: transport)
        }
        genericHIDFallbackTimer = timer
        genericHIDPendingFallbackDevice = device
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: timer)
    }

    func attemptGenericFallback(device: IOHIDDevice, vendorID: Int, productID: Int,
                                         version: Int, transport: String?) {
        genericHIDPendingFallbackDevice = nil

        // Don't activate if GameController framework connected in the meantime
        guard !isConnected else { return }

	let guid = GameControllerDatabase.constructGUID(
		vendorID: vendorID,
		productID: productID,
		version: version,
		transport: transport
	)
	let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
	let fallbackName = productName?.isEmpty == false ? productName! : "Generic HID Controller"
	let layout = HIDElementLayout.layout(for: device)
	guard let mapping = GameControllerDatabase.shared.lookup(
		vendorID: vendorID, productID: productID,
		version: version, transport: transport,
		compatibleWith: layout
	) ?? GenericHIDController.inferredMapping(
	    for: device,
	    fallbackName: fallbackName,
	    guid: guid
        ) else {
            #if DEBUG
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

        guard controller.start() else {
            #if DEBUG
            print("[GenericHID] Failed to open device for: \(mapping.name)")
            #endif
            return
        }
        genericHIDController = controller
        resetControllerTypeState()
        currentControllerIdentity = ControllerIdentityResolver.identity(for: device, fallbackName: mapping.name)
        isConnected = true
        isGenericController = true
        controllerName = mapping.name
        if let model = Self.eightBitDoMinimapModel(forControllerName: mapping.name) {
            storage.lock.lock()
            storage.eightBitDoModel = model
            storage.lock.unlock()
        }
		controllerMappingSource = mapping.platform == "Mac OS X" ? nil : "SDL \(mapping.platform) fallback"
        startDisplayUpdateTimer()

        #if DEBUG
        print("[GenericHID] Connected: \(mapping.name)")
        #endif
    }

    func genericDeviceRemoved(_ device: IOHIDDevice) {
        // Cancel a pending fallback armed for this device — otherwise the timer
        // could later promote a device that is already gone.
        if genericHIDPendingFallbackDevice == device {
            genericHIDFallbackTimer?.cancel()
            genericHIDFallbackTimer = nil
            genericHIDPendingFallbackDevice = nil
        }

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
    let holder = Unmanaged<GenericHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
    guard let service = holder.service else { return }
    DispatchQueue.main.async {
        service.genericDeviceAppeared(device)
    }
}

private nonisolated func genericHIDDeviceRemoved(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice) {
    guard let context = context else { return }
    let holder = Unmanaged<GenericHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
    guard let service = holder.service else { return }
    DispatchQueue.main.async {
        service.genericDeviceRemoved(device)
    }
}
