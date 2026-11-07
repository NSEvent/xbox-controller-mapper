import Combine
import Foundation
import IOKit
import IOKit.hid

// MARK: - Service (MainActor wiring)

/// Owns the foot pedal's lifecycle, mirroring `S29RingInputService`: starts HID
/// I/O once Input Monitoring is granted and mapping is enabled, stops it
/// (releasing held pedals and the exclusive seize) when mapping is disabled or
/// the app quits, and forwards pedal edges into `ControllerService` like any
/// other controller input.
@MainActor
final class FootPedalInputService {
	private let controllerService: ControllerService
	private let hardwareMonitoringEnabled: Bool
	private var session: FootPedalHIDSession?
	private var mappingEnabled = true
	private var mappingEnabledCancellable: AnyCancellable?

	init(controllerService: ControllerService, hardwareMonitoringEnabled: Bool = true) {
		self.controllerService = controllerService
		self.hardwareMonitoringEnabled = hardwareMonitoringEnabled && !AppRuntime.isRunningTests
	}

	func bindMappingEnabled<P: Publisher>(_ publisher: P) where P.Output == Bool, P.Failure == Never {
		mappingEnabledCancellable = publisher
			.removeDuplicates()
			.receive(on: DispatchQueue.main)
			.sink { [weak self] enabled in
				self?.setMappingEnabled(enabled)
			}
	}

	/// Opening the pedal needs Input Monitoring; callers re-invoke this when the
	/// permission is granted. Idempotent.
	func startIfPermitted() {
		guard hardwareMonitoringEnabled,
			  mappingEnabled,
			  session == nil,
			  SystemPermission.inputMonitoringGranted else { return }

		let controllerService = controllerService
		let session = FootPedalHIDSession(
			matching: FootPedalHIDDriverDescriptor().matchingCFArray,
			onEvent: { event in
				controllerService.controllerQueue.async {
					controllerService.handleButton(event.button, pressed: event.pressed)
				}
			},
			onConnectionChanged: { connected in
				DispatchQueue.main.async {
					MainActor.assumeIsolated {
						controllerService.setFootPedalConnected(connected)
					}
				}
			}
		)
		self.session = session
		session.start()
	}

	/// Releases held pedals, unregisters callbacks, and closes/unseizes the
	/// device. Safe to call repeatedly.
	func stop() {
		guard let session else { return }
		self.session = nil
		session.stop()
		controllerService.setFootPedalConnected(false)
	}

	private func setMappingEnabled(_ enabled: Bool) {
		mappingEnabled = enabled
		if enabled {
			startIfPermitted()
		} else {
			stop()
		}
	}
}

// MARK: - HID session (dedicated run-loop thread)

/// All IOKit work for the pedal runs on one dedicated run-loop thread, so the
/// decoder is only ever touched from that thread. A release report must never
/// queue behind a main-thread hitch, or a held key (push-to-talk) sticks down.
nonisolated final class FootPedalHIDSession: @unchecked Sendable {
	typealias EventHandler = @Sendable (FootPedalReportDecoder.Event) -> Void
	typealias ConnectionHandler = @Sendable (Bool) -> Void

	private static let minimumReportBufferSize = 8
	private static let runLoop = DedicatedHIDRunLoop(threadName: "ControllerKeys Foot Pedal HID")

	private let matching: CFArray
	private let onEvent: EventHandler
	private let onConnectionChanged: ConnectionHandler

	private struct OpenDevice {
		let device: IOHIDDevice
		let reportBuffer: UnsafeMutablePointer<UInt8>
		let reportBufferSize: Int
	}

	// Run-loop-thread state.
	private var manager: IOHIDManager?
	private var callbackContext: UnsafeMutableRawPointer?
	/// One decoder per pedal, so two pedals plugged in at once can't cancel
	/// each other's held state.
	private var devices: [(open: OpenDevice, decoder: FootPedalReportDecoder)] = []

	init(
		matching: CFArray,
		onEvent: @escaping EventHandler,
		onConnectionChanged: @escaping ConnectionHandler
	) {
		self.matching = matching
		self.onEvent = onEvent
		self.onConnectionChanged = onConnectionChanged
	}

	func start() {
		Self.runLoop.perform { [self] in
			startOnRunLoop()
		}
	}

	/// Blocks until teardown has run on the HID thread, so the pedal is
	/// unseized and every held pedal released before this returns.
	func stop() {
		let completed = Self.runLoop.performAndWait { [self] in
			stopOnRunLoop()
		}
		if !completed {
			NSLog("[ControllerKeys] Foot pedal HID teardown timed out; it will finish on the HID thread")
		}
	}

	// MARK: Lifecycle (HID thread)

	private func startOnRunLoop() {
		guard manager == nil else { return }

		let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
		let context = Unmanaged.passRetained(FootPedalHIDCallbackBox(session: self)).toOpaque()
		self.manager = manager
		self.callbackContext = context

		IOHIDManagerSetDeviceMatchingMultiple(manager, matching)
		IOHIDManagerRegisterDeviceMatchingCallback(manager, footPedalDeviceMatchedCallback, context)
		IOHIDManagerRegisterDeviceRemovalCallback(manager, footPedalDeviceRemovedCallback, context)
		IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

		if let matched = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
			for device in matched {
				deviceMatched(device)
			}
		}
	}

	private func stopOnRunLoop() {
		let wasConnected = !devices.isEmpty
		for index in devices.indices {
			deliver(devices[index].decoder.reset())
			teardown(devices[index].open, close: true)
		}
		devices.removeAll()

		if let manager {
			IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
			IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
			IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		}
		manager = nil

		if let callbackContext {
			Unmanaged<FootPedalHIDCallbackBox>.fromOpaque(callbackContext).release()
		}
		callbackContext = nil

		if wasConnected {
			onConnectionChanged(false)
		}
	}

	// MARK: Device matching (HID thread)

	fileprivate func deviceMatched(_ device: IOHIDDevice) {
		guard let callbackContext,
			  FootPedalIdentity.matches(device: device),
			  !devices.contains(where: { $0.open.device == device }) else { return }

		let maxReportSize = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
		let bufferSize = max(Self.minimumReportBufferSize, maxReportSize)
		let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
		buffer.initialize(repeating: 0, count: bufferSize)

		IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, footPedalInputReportCallback, callbackContext)

		// Exclusive open so no other app also acts on the pedal. Unlike the S29
		// ring there's no native behavior to fall back to: a refused seize means
		// another process (usually Karabiner-Elements) already holds it.
		let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
		guard openResult == kIOReturnSuccess else {
			NSLog(
				"[ControllerKeys] Foot pedal open returned 0x%08X; if Karabiner-Elements is running, turn off Modify events for \"VEC USB Footpedal\" in Karabiner → Devices",
				openResult
			)
			IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
			IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
			buffer.deallocate()
			return
		}

		let isFirstDevice = devices.isEmpty
		devices.append((
			open: OpenDevice(device: device, reportBuffer: buffer, reportBufferSize: bufferSize),
			decoder: FootPedalReportDecoder()
		))
		NSLog("[ControllerKeys] Foot pedal opened (%d connected)", devices.count)
		if isFirstDevice {
			onConnectionChanged(true)
		}
	}

	fileprivate func deviceRemoved(_ device: IOHIDDevice) {
		guard let index = devices.firstIndex(where: { $0.open.device == device }) else { return }
		var removed = devices.remove(at: index)
		deliver(removed.decoder.reset())
		// The device is already gone; closing would just fail.
		teardown(removed.open, close: false)
		guard devices.isEmpty else { return }
		NSLog("[ControllerKeys] Foot pedal disconnected")
		onConnectionChanged(false)
	}

	private func teardown(_ open: OpenDevice, close: Bool) {
		IOHIDDeviceRegisterInputReportCallback(open.device, open.reportBuffer, open.reportBufferSize, nil, nil)
		if close {
			IOHIDDeviceClose(open.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
		}
		IOHIDDeviceUnscheduleFromRunLoop(open.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		open.reportBuffer.deallocate()
	}

	// MARK: Input (HID thread)

	fileprivate func handleInputReport(from sender: UnsafeMutableRawPointer?, report: UnsafeMutablePointer<UInt8>, length: Int) {
		guard length > 0,
			  let index = devices.firstIndex(where: { Unmanaged.passUnretained($0.open.device).toOpaque() == sender })
				?? (devices.count == 1 ? 0 : nil) else { return }
		let bytes = Array(UnsafeBufferPointer(start: report, count: length))
		deliver(devices[index].decoder.process(report: bytes))
	}

	private func deliver(_ events: [FootPedalReportDecoder.Event]) {
		for event in events {
			onEvent(event)
		}
	}
}

// MARK: - IOKit C callbacks

/// Weak box handed to IOKit as callback context, so a late callback can never
/// touch a deallocated session.
nonisolated private final class FootPedalHIDCallbackBox {
	weak var session: FootPedalHIDSession?
	init(session: FootPedalHIDSession) { self.session = session }
}

nonisolated private func footPedalSession(from context: UnsafeMutableRawPointer?) -> FootPedalHIDSession? {
	guard let context else { return nil }
	return Unmanaged<FootPedalHIDCallbackBox>.fromOpaque(context).takeUnretainedValue().session
}

nonisolated private func footPedalDeviceMatchedCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	device: IOHIDDevice
) {
	footPedalSession(from: context)?.deviceMatched(device)
}

nonisolated private func footPedalDeviceRemovedCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	device: IOHIDDevice
) {
	footPedalSession(from: context)?.deviceRemoved(device)
}

nonisolated private func footPedalInputReportCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	type: IOHIDReportType,
	reportID: UInt32,
	report: UnsafeMutablePointer<UInt8>,
	reportLength: CFIndex
) {
	guard result == kIOReturnSuccess else { return }
	footPedalSession(from: context)?.handleInputReport(from: sender, report: report, length: Int(reportLength))
}
