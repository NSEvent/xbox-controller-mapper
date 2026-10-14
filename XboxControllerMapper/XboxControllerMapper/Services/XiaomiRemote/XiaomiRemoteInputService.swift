import AppKit
import Combine
import Foundation
import IOKit.hid

/// Exact-device HID lifecycle on the main run loop, following mapping and TCC.
/// Uses exclusive ownership where permitted, timestamp-scoped native-event
/// suppression otherwise. Never modifies another app's configuration.
@MainActor
final class XiaomiRemoteInputService {
	private let controller: ControllerService
	private let hardwareEnabled: Bool
	private var enabled = true
	private var mappingBinding: AnyCancellable?
	private var manager: IOHIDManager?
	private var device: IOHIDDevice?
	private var options: IOOptionBits = 0
	private var buffer: UnsafeMutablePointer<UInt8>?
	private var bufferSize = 0
	private var context: UnsafeMutableRawPointer?
	private var retryTimer: Timer?
	private var decoder = XiaomiRemoteReportDecoder()
	private var suppression = XiaomiRemoteNativeEventPolicy()
	private var tap: CFMachPort?
	private var tapSource: CFRunLoopSource?
	private var timestampScale: Double = 1e-9

	init(controller: ControllerService, hardwareEnabled: Bool = true) {
		self.controller = controller
		self.hardwareEnabled = hardwareEnabled && !AppRuntime.isRunningTests
		var timebase = mach_timebase_info_data_t()
		if mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 {
			timestampScale *= Double(timebase.numer) / Double(timebase.denom)
		}
	}

	func bindMappingEnabled<P: Publisher>(_ publisher: P) where P.Output == Bool, P.Failure == Never {
		mappingBinding = publisher.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] enabled in
			guard let self else { return }
			self.enabled = enabled
			if enabled { self.startIfPermitted() } else { self.stop() }
		}
	}

	func startIfPermitted() {
		guard hardwareEnabled, enabled, manager == nil, SystemPermission.inputMonitoringGranted else { return }
		let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
		self.manager = manager
		context = Unmanaged.passRetained(XiaomiRemoteCallbackBox(self)).toOpaque()
		IOHIDManagerSetDeviceMatchingMultiple(manager, XiaomiRemoteIdentity.transports.sorted().map {
			[kIOHIDVendorIDKey as String: XiaomiRemoteIdentity.vendorID,
			 kIOHIDProductIDKey as String: XiaomiRemoteIdentity.productID,
			 kIOHIDTransportKey as String: $0] as [String: Any]
		} as CFArray)
		IOHIDManagerRegisterDeviceMatchingCallback(manager, xiaomiRemoteMatched, context)
		IOHIDManagerRegisterDeviceRemovalCallback(manager, xiaomiRemoteRemoved, context)
		IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
		refreshDevices()
		retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.refreshDevices() }
		}
	}

	func stop() {
		retryTimer?.invalidate()
		retryTimer = nil
		closeDevice()
		if let manager {
			IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
			IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
			IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
		}
		manager = nil
		if let context { Unmanaged<XiaomiRemoteCallbackBox>.fromOpaque(context).release() }
		context = nil
		controller.xiaomiRemoteInputIssue = nil
	}

	private func refreshDevices() {
		guard device == nil, let manager,
			  let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
		for device in devices where self.device == nil { matched(device) }
	}

	fileprivate func matched(_ candidate: IOHIDDevice) {
		guard device == nil, XiaomiRemoteIdentity.matches(candidate), let context else { return }
		let exclusive = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
		var openOptions = exclusive
		var result = IOHIDDeviceOpen(candidate, exclusive)
		if result != kIOReturnSuccess {
			openOptions = 0
			result = IOHIDDeviceOpen(candidate, 0)
		}
		guard result == kIOReturnSuccess else {
			let issue = "Another app is using your Xiaomi remote. In Karabiner → Devices, turn off ‘Modify events’ for this remote."
			if controller.xiaomiRemoteInputIssue != issue {
				NSLog("[ControllerKeys] Xiaomi remote open failed: 0x%08X", result)
				controller.xiaomiRemoteInputIssue = issue
			}
			return
		}
		device = candidate
		options = openOptions
		bufferSize = max(121, IOHIDDeviceGetProperty(candidate, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 121)
		buffer = .allocate(capacity: bufferSize)
		buffer?.initialize(repeating: 0, count: bufferSize)
		IOHIDDeviceRegisterInputReportWithTimeStampCallback(candidate, buffer!, bufferSize, xiaomiRemoteReport, context)
		IOHIDDeviceScheduleWithRunLoop(candidate, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
		decoder = XiaomiRemoteReportDecoder()
		suppression = XiaomiRemoteNativeEventPolicy()
		controller.xiaomiRemoteInputIssue = nil
		if openOptions != exclusive { startSuppression() }
		controller.setXiaomiRemoteConnected(true, identity: ControllerIdentityResolver.identity(for: candidate, fallbackName: XiaomiRemoteIdentity.displayName))
		NSLog("[ControllerKeys] Xiaomi RC003 connected (%@)", openOptions == exclusive ? "exclusive" : "shared")
	}

	fileprivate func removed(_ candidate: IOHIDDevice) {
		guard device == candidate else { return }
		closeDevice()
		refreshDevices()
	}

	private func closeDevice() {
		stopSuppression()
		if let device, let buffer {
			IOHIDDeviceRegisterInputReportWithTimeStampCallback(device, buffer, bufferSize, nil, nil)
			IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
			IOHIDDeviceClose(device, options)
		}
		buffer?.deallocate()
		buffer = nil
		let wasConnected = device != nil
		device = nil
		deliver(decoder.reset())
		suppression = XiaomiRemoteNativeEventPolicy()
		if wasConnected { controller.setXiaomiRemoteConnected(false) }
	}

	fileprivate func report(_ bytes: [UInt8], reportID: UInt32, timestamp: UInt64) {
		guard device != nil else { return }
		let events = decoder.process(report: bytes, reportID: reportID)
		let held = Set(decoder.heldUsages.compactMap { XiaomiRemoteReportDecoder.buttonsByUsage[$0] })
		suppression.record(events, heldButtons: held, at: Double(timestamp) * timestampScale)
		deliver(events)
	}

	private func deliver(_ events: [XiaomiRemoteButtonEvent]) {
		for event in events {
			controller.controllerQueue.async { [controller] in
				controller.handleButton(event.button, pressed: event.pressed)
			}
		}
	}

	private func startSuppression() {
		guard tap == nil, let context else { return }
		let mask = CGEventMask((1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << 14))
		guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
			options: .defaultTap, eventsOfInterest: mask, callback: xiaomiRemoteNativeEvent, userInfo: context) else {
			controller.xiaomiRemoteInputIssue = "Allow ControllerKeys in Accessibility to prevent duplicate native remote actions."
			return
		}
		self.tap = tap
		tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
		if let tapSource { CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes) }
		CGEvent.tapEnable(tap: tap, enable: true)
	}

	private func stopSuppression() {
		if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
		if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
		tap = nil
		tapSource = nil
	}

	fileprivate func nativeEvent(_ event: CGEvent, type: CGEventType) -> Bool {
		if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
			if let tap, device != nil, enabled { CGEvent.tapEnable(tap: tap, enable: true) }
			return false
		}
		let control: XiaomiRemoteNativeEventPolicy.Control
		let pressed: Bool
		let repeated: Bool
		if type == .keyDown || type == .keyUp {
			control = .key(event.getIntegerValueField(.keyboardEventKeycode))
			pressed = type == .keyDown
			repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
		} else if type.rawValue == 14, let ns = NSEvent(cgEvent: event) {
			if ns.subtype.rawValue == 1 { control = .media(6); pressed = true; repeated = false }
			else if ns.subtype.rawValue == 8 {
				control = .media((ns.data1 >> 16) & 0xFFFF)
				pressed = ((ns.data1 >> 8) & 0xFF) == 0x0A
				repeated = (ns.data1 & 1) != 0
			} else { return false }
		} else { return false }
		return suppression.shouldSuppress(control, pressed: pressed, at: Double(event.timestamp) * 1e-9,
			keyboardType: event.getIntegerValueField(.keyboardEventKeyboardType), isRepeat: repeated,
			sourcePID: event.getIntegerValueField(.eventSourceUnixProcessID),
			synthetic: event.getIntegerValueField(.eventSourceUserData) == Config.controllerKeysSyntheticMediaEventUserData)
	}
}

nonisolated private final class XiaomiRemoteCallbackBox {
	weak var service: XiaomiRemoteInputService?
	init(_ service: XiaomiRemoteInputService) { self.service = service }
}

private nonisolated func xiaomiService(_ context: UnsafeMutableRawPointer?) -> XiaomiRemoteInputService? {
	context.map { Unmanaged<XiaomiRemoteCallbackBox>.fromOpaque($0).takeUnretainedValue().service } ?? nil
}

private nonisolated func xiaomiRemoteMatched(_ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ device: IOHIDDevice) {
	MainActor.assumeIsolated { xiaomiService(context)?.matched(device) }
}
private nonisolated func xiaomiRemoteRemoved(_ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ device: IOHIDDevice) {
	MainActor.assumeIsolated { xiaomiService(context)?.removed(device) }
}
private nonisolated func xiaomiRemoteReport(_ context: UnsafeMutableRawPointer?, _ result: IOReturn, _ sender: UnsafeMutableRawPointer?, _ type: IOHIDReportType, _ id: UInt32, _ report: UnsafeMutablePointer<UInt8>, _ count: CFIndex, _ timestamp: UInt64) {
	guard result == kIOReturnSuccess else { return }
	let bytes = Array(UnsafeBufferPointer(start: report, count: count))
	MainActor.assumeIsolated { xiaomiService(context)?.report(bytes, reportID: id, timestamp: timestamp) }
}
private nonisolated func xiaomiRemoteNativeEvent(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ context: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
	let suppress = MainActor.assumeIsolated { xiaomiService(context)?.nativeEvent(event, type: type) ?? false }
	return suppress ? nil : Unmanaged.passUnretained(event)
}
