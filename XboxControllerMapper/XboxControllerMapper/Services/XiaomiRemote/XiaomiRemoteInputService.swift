import AppKit
import Combine
import Foundation
import IOKit.hid

/// Exact-device HID lifecycle on the main run loop, following mapping and TCC.
/// Uses exclusive ownership where permitted, device-scoped native key
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
	private var nativeKeyMap: XiaomiRemoteNativeKeyMap?

	init(controller: ControllerService, hardwareEnabled: Bool = true) {
		self.controller = controller
		self.hardwareEnabled = hardwareEnabled && !AppRuntime.isRunningTests
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

		controller.xiaomiRemoteInputIssue = nil
		if openOptions != exclusive {
			let map = XiaomiRemoteNativeKeyMap()
			guard map.acquire() else {
				closeDevice()
				controller.xiaomiRemoteInputIssue = "Could not disable the Xiaomi remote’s native keys. Reconnect the remote to retry."
				return
			}
			nativeKeyMap = map
		}
		controller.setXiaomiRemoteConnected(true, identity: ControllerIdentityResolver.identity(for: candidate, fallbackName: XiaomiRemoteIdentity.displayName))
		NSLog("[ControllerKeys] Xiaomi RC003 connected (%@)", openOptions == exclusive ? "exclusive" : "shared")
	}

	fileprivate func removed(_ candidate: IOHIDDevice) {
		guard device == candidate else { return }
		closeDevice()
		refreshDevices()
	}

	private func closeDevice() {
		nativeKeyMap?.release()
		nativeKeyMap = nil
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

		if wasConnected { controller.setXiaomiRemoteConnected(false) }
	}

	fileprivate func report(_ bytes: [UInt8], reportID: UInt32, timestamp: UInt64) {
		guard device != nil else { return }
		let events = decoder.process(report: bytes, reportID: reportID)
		deliver(events)
	}

	private func deliver(_ events: [XiaomiRemoteButtonEvent]) {
		for event in events {
			controller.controllerQueue.async { [controller] in
				controller.handleButton(event.button, pressed: event.pressed)
			}
		}
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
