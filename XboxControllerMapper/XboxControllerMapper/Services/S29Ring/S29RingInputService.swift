import Combine
import Foundation
import IOKit
import IOKit.hid

// MARK: - Service (MainActor wiring)

/// Owns the S29 ring's lifecycle: starts HID I/O once Input Monitoring is
/// granted and mapping is enabled, stops it (releasing held buttons and the
/// exclusive seize) when mapping is disabled or the app quits, and forwards
/// decoded presses into `ControllerService` like any other controller input.
@MainActor
final class S29RingInputService {
	private let controllerService: ControllerService
	private let hardwareMonitoringEnabled: Bool
	private var session: S29RingHIDSession?
	private var mappingEnabled = true
	private var mappingEnabledCancellable: AnyCancellable?

	init(controllerService: ControllerService, hardwareMonitoringEnabled: Bool = true) {
		self.controllerService = controllerService
		self.hardwareMonitoringEnabled = hardwareMonitoringEnabled && !AppRuntime.isRunningTests
	}

	/// Follows the mapping on/off switch: disabling mapping hands the ring back
	/// to macOS (unseize) so its native swipe/volume actions work again.
	func bindMappingEnabled<P: Publisher>(_ publisher: P) where P.Output == Bool, P.Failure == Never {
		mappingEnabledCancellable = publisher
			.removeDuplicates()
			.receive(on: DispatchQueue.main)
			.sink { [weak self] enabled in
				self?.setMappingEnabled(enabled)
			}
	}

	/// Opening the ring needs Input Monitoring; callers re-invoke this when the
	/// permission is granted. Idempotent.
	func startIfPermitted() {
		guard hardwareMonitoringEnabled,
			  mappingEnabled,
			  session == nil,
			  SystemPermission.inputMonitoringGranted else { return }

		let controllerService = controllerService
		let session = S29RingHIDSession(
			matching: S29RingHIDDriverDescriptor().matchingCFArray,
			onEvent: { event in
				let button = event.control.button
				let pressed = event.pressed
				controllerService.controllerQueue.async {
					controllerService.handleButton(button, pressed: pressed)
				}
			},
			onConnectionChanged: { connected in
				DispatchQueue.main.async {
					MainActor.assumeIsolated {
						controllerService.setS29RingConnected(connected)
					}
				}
			}
		)
		self.session = session
		session.start()
	}

	/// Releases held ring buttons, unregisters callbacks, and closes/unseizes
	/// the device. Safe to call repeatedly.
	func stop() {
		guard let session else { return }
		self.session = nil
		session.stop()
		controllerService.setS29RingConnected(false)
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

/// All IOKit work for the ring — matching, the exclusive open, report
/// callbacks, and the decoder's deadline timer — runs on one dedicated
/// run-loop thread, so the decoder is only ever touched from that thread.
///
/// A Bluetooth LE HID peripheral can surface as more than one IOHIDDevice
/// (one per HID service) sharing the same identity, so every matching
/// interface is seized and fed into the single decoder — reports carry their
/// own report IDs. Leaving an interface unseized would let macOS keep acting
/// on its events.
nonisolated final class S29RingHIDSession: @unchecked Sendable {
	typealias EventHandler = @Sendable (S29RingEvent) -> Void
	typealias ConnectionHandler = @Sendable (Bool) -> Void

	private static let minimumReportBufferSize = 64
	private static let runLoopThread = S29RingRunLoopThread()

	private let matching: CFArray
	private let onEvent: EventHandler
	private let onConnectionChanged: ConnectionHandler
	private let clock: @Sendable () -> TimeInterval

	private struct OpenInterface {
		let device: IOHIDDevice
		let openOptions: IOOptionBits
		let reportBuffer: UnsafeMutablePointer<UInt8>
		let reportBufferSize: Int
	}

	// Run-loop-thread state.
	private var manager: IOHIDManager?
	private var callbackContext: UnsafeMutableRawPointer?
	private var interfaces: [OpenInterface] = []
	private var deadlineTimer: CFRunLoopTimer?
	private var decoder = S29RingReportDecoder()

	init(
		matching: CFArray,
		onEvent: @escaping EventHandler,
		onConnectionChanged: @escaping ConnectionHandler,
		clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
	) {
		self.matching = matching
		self.onEvent = onEvent
		self.onConnectionChanged = onConnectionChanged
		self.clock = clock
	}

	func start() {
		Self.runLoopThread.perform { [self] in
			startOnRunLoop()
		}
	}

	/// Blocks until teardown has run on the HID thread, so the device is
	/// unseized and every held button released before this returns.
	func stop() {
		let completed = Self.runLoopThread.performAndWait { [self] in
			stopOnRunLoop()
		}
		if !completed {
			NSLog("[ControllerKeys] S29 ring HID teardown timed out; it will finish on the HID thread")
		}
	}

	// MARK: Lifecycle (HID thread)

	private func startOnRunLoop() {
		guard manager == nil else { return }

		let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
		let context = Unmanaged.passRetained(S29RingHIDCallbackBox(session: self)).toOpaque()
		self.manager = manager
		self.callbackContext = context

		IOHIDManagerSetDeviceMatchingMultiple(manager, matching)
		IOHIDManagerRegisterDeviceMatchingCallback(manager, s29RingDeviceMatchedCallback, context)
		IOHIDManagerRegisterDeviceRemovalCallback(manager, s29RingDeviceRemovedCallback, context)
		IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		// Deliberately no IOHIDManagerOpen: that would open every candidate.
		// Only a device that passes the full identity check is opened, below.

		let timer = CFRunLoopTimerCreateWithHandler(
			kCFAllocatorDefault,
			.greatestFiniteMagnitude,
			.greatestFiniteMagnitude,
			0,
			0
		) { [weak self] _ in
			self?.deadlineTimerFired()
		}
		if let timer {
			CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
			deadlineTimer = timer
		}

		if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
			for device in devices {
				deviceMatched(device)
			}
		}
	}

	private func stopOnRunLoop() {
		let wasConnected = !interfaces.isEmpty
		for interface in interfaces {
			teardown(interface, close: true)
		}
		interfaces.removeAll()
		deliver(decoder.reset())
		rescheduleDeadlineTimer()

		if let manager {
			IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
			IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
			IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		}
		manager = nil

		if let deadlineTimer {
			CFRunLoopTimerInvalidate(deadlineTimer)
		}
		deadlineTimer = nil

		// Every callback that could use the context is unregistered and
		// unscheduled on this same thread, so it's safe to release now.
		if let callbackContext {
			Unmanaged<S29RingHIDCallbackBox>.fromOpaque(callbackContext).release()
		}
		callbackContext = nil

		if wasConnected {
			onConnectionChanged(false)
		}
	}

	// MARK: Device matching (HID thread)

	fileprivate func deviceMatched(_ device: IOHIDDevice) {
		guard let callbackContext,
			  !interfaces.contains(where: { $0.device == device }) else { return }

		guard S29RingIdentity.matches(device: device) else {
			// Same spoofed VID/PID as a real Apple keyboard — never touch it.
			let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
			let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
			NSLog(
				"[ControllerKeys] S29 ring: ignoring VID/PID match that is not an S29 (product=%@ transport=%@)",
				productName ?? "(nil)",
				transport ?? "(nil)"
			)
			return
		}

		let maxReportSize = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int ?? 0
		let bufferSize = max(Self.minimumReportBufferSize, maxReportSize)
		let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
		buffer.initialize(repeating: 0, count: bufferSize)

		IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, s29RingInputReportCallback, callbackContext)

		// Exclusive open so macOS stops acting on the ring's mouse/volume
		// events. Mirror the Steam Controller fallback: if the seize is refused,
		// keep the ring usable with a shared open and say so in the log.
		let seizeOptions = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
		var openOptions = seizeOptions
		var openResult = IOHIDDeviceOpen(device, seizeOptions)
		if openResult != kIOReturnSuccess {
			NSLog("[ControllerKeys] S29 ring seize returned 0x%08X; falling back to shared open (native ring actions stay active)", openResult)
			openOptions = IOOptionBits(kIOHIDOptionsTypeNone)
			openResult = IOHIDDeviceOpen(device, openOptions)
		}
		guard openResult == kIOReturnSuccess else {
			NSLog("[ControllerKeys] S29 ring open returned 0x%08X", openResult)
			IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
			IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
			buffer.deallocate()
			return
		}

		let isFirstInterface = interfaces.isEmpty
		interfaces.append(OpenInterface(
			device: device,
			openOptions: openOptions,
			reportBuffer: buffer,
			reportBufferSize: bufferSize
		))
		NSLog(
			"[ControllerKeys] S29 ring interface opened (%@, %d open)",
			openOptions == seizeOptions ? "seized" : "shared",
			interfaces.count
		)
		if isFirstInterface {
			decoder = S29RingReportDecoder()
			onConnectionChanged(true)
		}
	}

	fileprivate func deviceRemoved(_ device: IOHIDDevice) {
		guard let index = interfaces.firstIndex(where: { $0.device == device }) else { return }
		// The device is already gone; closing would just fail.
		teardown(interfaces.remove(at: index), close: false)
		guard interfaces.isEmpty else { return }
		deliver(decoder.reset())
		rescheduleDeadlineTimer()
		NSLog("[ControllerKeys] S29 ring disconnected")
		onConnectionChanged(false)
	}

	private func teardown(_ interface: OpenInterface, close: Bool) {
		IOHIDDeviceRegisterInputReportCallback(
			interface.device,
			interface.reportBuffer,
			interface.reportBufferSize,
			nil,
			nil
		)
		if close {
			IOHIDDeviceClose(interface.device, interface.openOptions)
		}
		IOHIDDeviceUnscheduleFromRunLoop(interface.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		interface.reportBuffer.deallocate()
	}

	// MARK: Input (HID thread)

	fileprivate func handleInputReport(_ report: UnsafeMutablePointer<UInt8>, length: Int) {
		guard !interfaces.isEmpty, length > 0 else { return }
		let bytes = Array(UnsafeBufferPointer(start: report, count: length))
		deliver(decoder.process(report: bytes, at: clock()))
		rescheduleDeadlineTimer()
	}

	private func deadlineTimerFired() {
		deliver(decoder.advance(to: clock()))
		rescheduleDeadlineTimer()
	}

	private func rescheduleDeadlineTimer() {
		guard let deadlineTimer else { return }
		guard let deadline = decoder.nextDeadline else {
			CFRunLoopTimerSetNextFireDate(deadlineTimer, .greatestFiniteMagnitude)
			return
		}
		let delay = max(0, deadline - clock())
		CFRunLoopTimerSetNextFireDate(deadlineTimer, CFAbsoluteTimeGetCurrent() + delay)
	}

	private func deliver(_ events: [S29RingEvent]) {
		for event in events {
			onEvent(event)
		}
	}
}

// MARK: - IOKit C callbacks

/// Weak box handed to IOKit as callback context, so a late callback can never
/// touch a deallocated session.
nonisolated private final class S29RingHIDCallbackBox {
	weak var session: S29RingHIDSession?
	init(session: S29RingHIDSession) { self.session = session }
}

nonisolated private func s29RingSession(from context: UnsafeMutableRawPointer?) -> S29RingHIDSession? {
	guard let context else { return nil }
	return Unmanaged<S29RingHIDCallbackBox>.fromOpaque(context).takeUnretainedValue().session
}

nonisolated private func s29RingDeviceMatchedCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	device: IOHIDDevice
) {
	s29RingSession(from: context)?.deviceMatched(device)
}

nonisolated private func s29RingDeviceRemovedCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	device: IOHIDDevice
) {
	s29RingSession(from: context)?.deviceRemoved(device)
}

nonisolated private func s29RingInputReportCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	type: IOHIDReportType,
	reportID: UInt32,
	report: UnsafeMutablePointer<UInt8>,
	reportLength: CFIndex
) {
	guard result == kIOReturnSuccess else { return }
	s29RingSession(from: context)?.handleInputReport(report, length: Int(reportLength))
}

// MARK: - Run-loop thread

/// A long-lived thread running a CFRunLoop for S29 HID callbacks (same shape
/// as the Steam Controller HID thread). Started lazily on first use.
nonisolated private final class S29RingRunLoopThread: @unchecked Sendable {
	private let lock = NSLock()
	private var runLoop: CFRunLoop?

	func perform(_ work: @escaping @Sendable () -> Void) {
		let runLoop = startIfNeeded()
		CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
		CFRunLoopWakeUp(runLoop)
	}

	/// Returns false when the wait timed out; the work may still run later.
	@discardableResult
	func performAndWait(_ work: @escaping @Sendable () -> Void) -> Bool {
		let semaphore = DispatchSemaphore(value: 0)
		perform {
			work()
			semaphore.signal()
		}
		return semaphore.wait(timeout: .now() + 1.0) == .success
	}

	private func startIfNeeded() -> CFRunLoop {
		lock.lock()
		if let runLoop {
			lock.unlock()
			return runLoop
		}

		let ready = DispatchSemaphore(value: 0)
		let thread = Thread { [self] in
			let currentRunLoop = CFRunLoopGetCurrent()
			var sourceContext = CFRunLoopSourceContext()
			if let keepAliveSource = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceContext) {
				CFRunLoopAddSource(currentRunLoop, keepAliveSource, CFRunLoopMode.defaultMode)
			}
			lock.lock()
			runLoop = currentRunLoop
			lock.unlock()
			ready.signal()
			CFRunLoopRun()
		}
		thread.name = "ControllerKeys S29 Ring HID"
		thread.qualityOfService = .userInteractive
		thread.start()
		lock.unlock()

		ready.wait()
		lock.lock()
		let currentRunLoop = runLoop!
		lock.unlock()
		return currentRunLoop
	}
}
