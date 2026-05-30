import Foundation
import AppKit
import CoreGraphics
import IOKit
import IOKit.hid

// MARK: - Apple TV/Siri Remote HID Monitoring (buttons + touch surface)

fileprivate final class AppleTVRemoteHIDCallbackContext {
	weak var service: ControllerService?
	init(service: ControllerService) { self.service = service }
}

fileprivate final class AppleTVRemoteSystemEventTapContext: @unchecked Sendable {
	weak var service: ControllerService?
	init(service: ControllerService) { self.service = service }
}

struct AppleTVRemoteTouchPoint: Equatable {
	let position: CGPoint
	let pressure: UInt8
}

struct AppleTVRemoteTouchReport: Equatable {
	let primary: AppleTVRemoteTouchPoint?
	let secondary: AppleTVRemoteTouchPoint?

	var isTouching: Bool {
		primary != nil || secondary != nil
	}
}

private enum AppleTVRemoteHID {
	static let appleVendorID = 0x05AC
	static let appleBluetoothCompanyID = 76
	static let knownBluetoothRemoteProductIDs: Set<Int> = [614, 621, 788, 789]
	static let genericDesktopUsagePage: UInt32 = 0x01
	static let digitizerUsagePage: UInt32 = 0x0D
	static let digitizerUsage: UInt32 = 0x01
	static let consumerUsagePage: UInt32 = 0x0C
	static let microphoneUsage: UInt32 = 0x04
	static let powerUsage: UInt32 = 0x30
	static let menuUsage: UInt32 = 0x40
	static let menuPickUsage: UInt32 = 0x41
	static let menuUpUsage: UInt32 = 0x42
	static let menuDownUsage: UInt32 = 0x43
	static let menuLeftUsage: UInt32 = 0x44
	static let menuRightUsage: UInt32 = 0x45
	static let menuEscapeUsage: UInt32 = 0x46
	static let dataOnScreenUsage: UInt32 = 0x60
		static let selectionUsage: UInt32 = 0x80
	    static let playUsage: UInt32 = 0xB0
	    static let pauseUsage: UInt32 = 0xB1
		static let playPauseUsage: UInt32 = 0xCD
		static let muteUsage: UInt32 = 0xE2
		static let volumeUpUsage: UInt32 = 0xE9
		static let volumeDownUsage: UInt32 = 0xEA
		static let voiceCommandUsage: UInt32 = 0x00CF
		static let systemAppMenuUsage: UInt32 = 0x86
		static let touchReleaseDelay: TimeInterval = 0.15
		static let systemEventSuppressionWindow: TimeInterval = 0.50
		static let cgEventTypeSystemDefinedRawValue: UInt32 = 14
		static let powerButtonSubtype: Int16 = 1
		static let auxControlButtonSubtype: Int16 = 8
		static let nxKeyTypeSoundUp = 0
		static let nxKeyTypeSoundDown = 1
		static let nxKeyTypePower = 6
		static let nxKeyTypeMute = 7
	static let defaultTouchReportBufferSize = 256
	static let currentRemoteTouchReportLength = 11
	static let firstGenerationOneFingerTouchReportLength = 13
	static let firstGenerationTwoFingerTouchReportLength = 20
	static let firstGenerationTouchEventMarker: UInt8 = 50
	static let touchMaxX: CGFloat = 150
	static let touchMaxY: CGFloat = 105
}

@MainActor
extension ControllerService {

	func setupAppleTVRemoteHIDMonitoring() {
		if appleTVRemoteHIDManager != nil || appleTVRemoteHIDButtonManager != nil {
			cleanupAppleTVRemoteHIDMonitoring()
		}

		let ctx = AppleTVRemoteHIDCallbackContext(service: self)
		let retainedContext = Unmanaged.passRetained(ctx).toOpaque()
		appleTVRemoteHIDCallbackContext = retainedContext

		setupAppleTVRemoteButtonHIDManager(context: retainedContext)

		let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
		appleTVRemoteHIDManager = manager

		let matching = Self.appleTVRemoteTouchHIDMatchingCriteria()
		IOHIDManagerSetDeviceMatchingMultiple(manager, matching)
		IOHIDManagerRegisterDeviceMatchingCallback(manager, appleTVRemoteHIDDeviceMatchedCallback, retainedContext)
		IOHIDManagerRegisterDeviceRemovalCallback(manager, appleTVRemoteHIDDeviceRemovedCallback, retainedContext)
		IOHIDManagerRegisterInputValueCallback(manager, appleTVRemoteHIDInputValueCallback, retainedContext)

		IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
		if openResult != kIOReturnSuccess {
			NSLog("[ControllerKeys] Apple TV Remote HID manager open returned 0x%08X", openResult)
		}

		if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
			for device in devices {
				appleTVRemoteHIDDeviceAppeared(device)
			}
		}

		// The Siri Remote touch surface is consumed by Apple's multitouch driver on
		// current remotes, so the digitizer HID child is not always enough.
		_ = setupAppleTVRemoteMultitouchMonitoring()
	}

	private func setupAppleTVRemoteButtonHIDManager(context: UnsafeMutableRawPointer) {
		let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
		appleTVRemoteHIDButtonManager = manager

		IOHIDManagerSetDeviceMatchingMultiple(manager, Self.appleTVRemoteButtonHIDMatchingCriteria())
		IOHIDManagerRegisterDeviceMatchingCallback(manager, appleTVRemoteHIDDeviceMatchedCallback, context)
		IOHIDManagerRegisterDeviceRemovalCallback(manager, appleTVRemoteHIDDeviceRemovedCallback, context)
		IOHIDManagerRegisterInputValueCallback(manager, appleTVRemoteHIDInputValueCallback, context)
		IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

		let seizeOptions = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
		let seizeResult = IOHIDManagerOpen(manager, seizeOptions)
		if seizeResult == kIOReturnSuccess {
			appleTVRemoteHIDButtonManagerOpenOptions = seizeOptions
			NSLog("[ControllerKeys] Apple TV Remote consumer-control HID manager seized")
		} else {
			NSLog("[ControllerKeys] Apple TV Remote consumer-control HID manager seize returned 0x%08X; using event suppression fallback", seizeResult)
			let fallbackResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
			if fallbackResult != kIOReturnSuccess {
				NSLog("[ControllerKeys] Apple TV Remote consumer-control HID manager open returned 0x%08X", fallbackResult)
			}
			appleTVRemoteHIDButtonManagerOpenOptions = IOOptionBits(kIOHIDOptionsTypeNone)
		}

		if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
			for device in devices {
				appleTVRemoteHIDDeviceAppeared(device)
			}
		}
	}

	func cleanupAppleTVRemoteHIDMonitoring() {
		storage.lock.lock()
		storage.appleTVRemoteTouchReleaseWorkItem?.cancel()
		storage.appleTVRemoteTouchReleaseWorkItem = nil
		storage.appleTVRemoteActiveSystemKeyTypes.removeAll()
		storage.appleTVRemoteSystemKeyTypeSuppressUntil.removeAll()
		storage.lock.unlock()

		if appleTVRemoteMultitouchStarted || CKAppleTVRemoteMultitouchIsRunning() {
			CKAppleTVRemoteMultitouchStop()
			appleTVRemoteMultitouchStarted = false
		}

		stopAppleTVRemoteSystemEventSuppression()

		if let device = appleTVRemoteHIDTouchDevice,
		   let buffer = appleTVRemoteHIDTouchReportBuffer {
			IOHIDDeviceRegisterInputReportCallback(
				device,
				buffer,
				appleTVRemoteHIDTouchReportBufferSize,
				nil,
				nil
			)
			IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		}
		appleTVRemoteHIDTouchDevice = nil

			if let manager = appleTVRemoteHIDManager {
				IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
				IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
				IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
				IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
				IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
			}
			if let manager = appleTVRemoteHIDButtonManager {
				IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
				IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
				IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
				IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
				IOHIDManagerClose(manager, appleTVRemoteHIDButtonManagerOpenOptions)
			}
			appleTVRemoteHIDManager = nil
			appleTVRemoteHIDButtonManager = nil
			appleTVRemoteHIDDevice = nil
			appleTVRemoteHIDButtonManagerOpenOptions = IOOptionBits(kIOHIDOptionsTypeNone)
			appleTVRemoteHIDTouchReportBuffer?.deallocate()
		appleTVRemoteHIDTouchReportBuffer = nil
		appleTVRemoteHIDTouchReportBufferSize = 0

		if let ctx = appleTVRemoteHIDCallbackContext {
			Unmanaged<AppleTVRemoteHIDCallbackContext>.fromOpaque(ctx).release()
			appleTVRemoteHIDCallbackContext = nil
		}
	}

	func appleTVRemoteHIDDeviceAppeared(_ device: IOHIDDevice) {
		if Self.isAppleTVRemoteHIDDevice(device) {
			appleTVRemoteHIDDevice = device
			startAppleTVRemoteSystemEventSuppression()
			NSLog("[ControllerKeys] Apple TV Remote HID monitoring started for buttons: %@",
				  Self.appleTVRemoteHIDDeviceName(device))
			activateAppleTVRemoteHIDSessionIfNeeded(device)
		}

		if Self.isAppleTVRemoteTouchHIDDevice(device) {
			if !setupAppleTVRemoteMultitouchMonitoring() {
				setupAppleTVRemoteTouchReportCallback(device)
			}
			activateAppleTVRemoteHIDSessionIfNeeded(device)
		}
	}

	func appleTVRemoteHIDDeviceRemoved(_ device: IOHIDDevice) {
		var removedRemoteDevice = false
			if appleTVRemoteHIDDevice == device {
				appleTVRemoteHIDDevice = nil
				removedRemoteDevice = true
				controllerQueue.async { [weak self] in
					self?.releaseAppleTVRemoteButtonsIfNeeded()
				}
			}

		if appleTVRemoteHIDTouchDevice == device {
			if let buffer = appleTVRemoteHIDTouchReportBuffer {
				IOHIDDeviceRegisterInputReportCallback(
					device,
					buffer,
					appleTVRemoteHIDTouchReportBufferSize,
					nil,
					nil
				)
				IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
				buffer.deallocate()
				appleTVRemoteHIDTouchReportBuffer = nil
				appleTVRemoteHIDTouchReportBufferSize = 0
			}
			appleTVRemoteHIDTouchDevice = nil
			removedRemoteDevice = true
			releaseAppleTVRemoteTouchIfStillActive()
		}

		if removedRemoteDevice,
		   appleTVRemoteMultitouchStarted || CKAppleTVRemoteMultitouchIsRunning() {
			CKAppleTVRemoteMultitouchStop()
			appleTVRemoteMultitouchStarted = false
			releaseAppleTVRemoteTouchIfStillActive()
		}

		if removedRemoteDevice, connectedController == nil {
			controllerDisconnected()
		}
	}

	@discardableResult
	private func setupAppleTVRemoteMultitouchMonitoring() -> Bool {
		guard let context = appleTVRemoteHIDCallbackContext else { return false }
		let started = CKAppleTVRemoteMultitouchStart(context, appleTVRemoteMultitouchCallback)
		if started, !appleTVRemoteMultitouchStarted {
			NSLog("[ControllerKeys] Apple TV Remote multitouch monitoring started")
		}
		appleTVRemoteMultitouchStarted = started || appleTVRemoteMultitouchStarted
		return started
	}

	private func setupAppleTVRemoteTouchReportCallback(_ device: IOHIDDevice) {
		if appleTVRemoteHIDTouchDevice == device {
			return
		}

		if let existingDevice = appleTVRemoteHIDTouchDevice,
		   let existingBuffer = appleTVRemoteHIDTouchReportBuffer {
			IOHIDDeviceRegisterInputReportCallback(
				existingDevice,
				existingBuffer,
				appleTVRemoteHIDTouchReportBufferSize,
				nil,
				nil
			)
			IOHIDDeviceUnscheduleFromRunLoop(existingDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
			existingBuffer.deallocate()
			appleTVRemoteHIDTouchReportBuffer = nil
			appleTVRemoteHIDTouchReportBufferSize = 0
		}

		guard let context = appleTVRemoteHIDCallbackContext else { return }
		let maxInputReportSize = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int
		let bufferSize = max(maxInputReportSize ?? 0, AppleTVRemoteHID.defaultTouchReportBufferSize)
		let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
		buffer.initialize(repeating: 0, count: bufferSize)

		appleTVRemoteHIDTouchDevice = device
		appleTVRemoteHIDTouchReportBuffer = buffer
		appleTVRemoteHIDTouchReportBufferSize = bufferSize

		IOHIDDeviceRegisterInputReportCallback(
			device,
			buffer,
			bufferSize,
			appleTVRemoteHIDInputReportCallback,
			context
		)
		IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		NSLog("[ControllerKeys] Apple TV Remote HID monitoring started for touch surface: %@",
			  Self.appleTVRemoteHIDDeviceName(device))
	}

	private func startAppleTVRemoteSystemEventSuppression() {
		guard appleTVRemoteSystemEventTap == nil else { return }

		let context = AppleTVRemoteSystemEventTapContext(service: self)
		let retainedContext = Unmanaged.passRetained(context).toOpaque()
		let eventMask = CGEventMask(1 << AppleTVRemoteHID.cgEventTypeSystemDefinedRawValue)

		guard let tap = CGEvent.tapCreate(
			tap: .cghidEventTap,
			place: .headInsertEventTap,
			options: .defaultTap,
			eventsOfInterest: eventMask,
			callback: appleTVRemoteSystemEventTapCallback,
			userInfo: retainedContext
		) else {
			Unmanaged<AppleTVRemoteSystemEventTapContext>.fromOpaque(retainedContext).release()
			NSLog("[ControllerKeys] Apple TV Remote system event suppression tap could not be created")
			return
		}

		let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
		CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)
		CGEvent.tapEnable(tap: tap, enable: true)

		appleTVRemoteSystemEventTap = tap
		appleTVRemoteSystemEventRunLoopSource = source
		appleTVRemoteSystemEventTapContext = retainedContext
		NSLog("[ControllerKeys] Apple TV Remote system event suppression started")
	}

	private func stopAppleTVRemoteSystemEventSuppression() {
		if let tap = appleTVRemoteSystemEventTap {
			CGEvent.tapEnable(tap: tap, enable: false)
		}
		if let source = appleTVRemoteSystemEventRunLoopSource {
			CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.commonModes)
		}
		appleTVRemoteSystemEventTap = nil
		appleTVRemoteSystemEventRunLoopSource = nil
		if let context = appleTVRemoteSystemEventTapContext {
			Unmanaged<AppleTVRemoteSystemEventTapContext>.fromOpaque(context).release()
			appleTVRemoteSystemEventTapContext = nil
		}
	}

	nonisolated func reenableAppleTVRemoteSystemEventSuppressionIfNeeded() {
		Task { @MainActor [weak self] in
			guard let tap = self?.appleTVRemoteSystemEventTap else { return }
			CGEvent.tapEnable(tap: tap, enable: true)
		}
	}

	nonisolated static func appleTVRemoteButtonForHIDUsage(usagePage: UInt32, usage: UInt32) -> ControllerButton? {
		if usagePage == AppleTVRemoteHID.genericDesktopUsagePage {
			if usage == AppleTVRemoteHID.systemAppMenuUsage {
				return .view
			}
			return nil
		}

		guard usagePage == AppleTVRemoteHID.consumerUsagePage else {
			return nil
		}

		switch usage {
		case AppleTVRemoteHID.microphoneUsage, AppleTVRemoteHID.voiceCommandUsage:
			return .siri
		case AppleTVRemoteHID.selectionUsage, AppleTVRemoteHID.menuPickUsage:
			return .a
		case AppleTVRemoteHID.playUsage, AppleTVRemoteHID.pauseUsage, AppleTVRemoteHID.playPauseUsage:
			return .menu
		case AppleTVRemoteHID.menuUsage, AppleTVRemoteHID.menuEscapeUsage:
			return .view
		case AppleTVRemoteHID.dataOnScreenUsage:
			return .xbox
		case AppleTVRemoteHID.powerUsage:
			return .appleTVRemotePower
		case AppleTVRemoteHID.volumeUpUsage:
			return .appleTVRemoteVolumeUp
		case AppleTVRemoteHID.volumeDownUsage:
			return .appleTVRemoteVolumeDown
		case AppleTVRemoteHID.muteUsage:
			return .appleTVRemoteMute
		case AppleTVRemoteHID.menuUpUsage:
			return .dpadUp
		case AppleTVRemoteHID.menuDownUsage:
			return .dpadDown
		case AppleTVRemoteHID.menuLeftUsage:
			return .dpadLeft
		case AppleTVRemoteHID.menuRightUsage:
			return .dpadRight
		default:
			return nil
		}
	}

	nonisolated func handleAppleTVRemoteHIDValue(_ value: IOHIDValue) {
		let element = IOHIDValueGetElement(value)
		let device = IOHIDElementGetDevice(element)
		guard Self.isAppleTVRemoteHIDDevice(device) else { return }

		let usagePage = IOHIDElementGetUsagePage(element)
			let usage = IOHIDElementGetUsage(element)
			guard let button = Self.appleTVRemoteButtonForHIDUsage(usagePage: usagePage, usage: usage) else { return }

			let isPressed = IOHIDValueGetIntegerValue(value) != 0
			let now = CFAbsoluteTimeGetCurrent()
			storage.lock.lock()
			storage.lastInputTime = now
			if let systemKeyType = Self.appleTVRemoteSystemKeyType(for: button) {
				if isPressed {
					storage.appleTVRemoteActiveSystemKeyTypes.insert(systemKeyType)
				} else {
					storage.appleTVRemoteActiveSystemKeyTypes.remove(systemKeyType)
				}
				storage.appleTVRemoteSystemKeyTypeSuppressUntil[systemKeyType] = now + AppleTVRemoteHID.systemEventSuppressionWindow
			}
			storage.lock.unlock()

			controllerQueue.async { [weak self] in
				self?.handleButton(button, pressed: isPressed)
			}
		}

	nonisolated static func appleTVRemoteSystemKeyType(for button: ControllerButton) -> Int? {
		switch button {
		case .appleTVRemoteVolumeUp:
			return AppleTVRemoteHID.nxKeyTypeSoundUp
		case .appleTVRemoteVolumeDown:
			return AppleTVRemoteHID.nxKeyTypeSoundDown
		case .appleTVRemotePower:
			return AppleTVRemoteHID.nxKeyTypePower
		case .appleTVRemoteMute:
			return AppleTVRemoteHID.nxKeyTypeMute
		default:
			return nil
		}
	}

	nonisolated func shouldSuppressAppleTVRemoteSystemEvent(_ event: CGEvent, type: CGEventType) -> Bool {
		guard type.rawValue == AppleTVRemoteHID.cgEventTypeSystemDefinedRawValue,
			  event.getIntegerValueField(.eventSourceUserData) != Config.controllerKeysSyntheticMediaEventUserData,
			  let nsEvent = NSEvent(cgEvent: event) else {
			return false
		}

		let keyType: Int
		switch nsEvent.subtype.rawValue {
		case AppleTVRemoteHID.powerButtonSubtype:
			keyType = AppleTVRemoteHID.nxKeyTypePower
		case AppleTVRemoteHID.auxControlButtonSubtype:
			keyType = (nsEvent.data1 >> 16) & 0xFFFF
			guard [
				AppleTVRemoteHID.nxKeyTypeSoundUp,
				AppleTVRemoteHID.nxKeyTypeSoundDown,
				AppleTVRemoteHID.nxKeyTypePower,
				AppleTVRemoteHID.nxKeyTypeMute
			].contains(keyType) else {
				return false
			}
		default:
			return false
		}

		let now = CFAbsoluteTimeGetCurrent()
		storage.lock.lock()
		let shouldSuppress = storage.isAppleTVRemote &&
			(storage.appleTVRemoteActiveSystemKeyTypes.contains(keyType) ||
			 (storage.appleTVRemoteSystemKeyTypeSuppressUntil[keyType] ?? 0) > now ||
			 keyType == AppleTVRemoteHID.nxKeyTypeSoundUp ||
			 keyType == AppleTVRemoteHID.nxKeyTypeSoundDown ||
			 keyType == AppleTVRemoteHID.nxKeyTypePower ||
			 keyType == AppleTVRemoteHID.nxKeyTypeMute)
		if !shouldSuppress {
			storage.appleTVRemoteSystemKeyTypeSuppressUntil = storage.appleTVRemoteSystemKeyTypeSuppressUntil.filter { $0.value > now }
		}
		storage.lock.unlock()
		return shouldSuppress
	}

	nonisolated func handleAppleTVRemoteTouchReport(
		reportID: UInt32,
		report: UnsafePointer<UInt8>,
		length: Int
	) {
		guard let touchReport = Self.appleTVRemoteTouchReport(
			reportID: reportID,
			report: report,
			length: length
		) else { return }

		storage.lock.lock()
		storage.lastInputTime = CFAbsoluteTimeGetCurrent()
		storage.lock.unlock()

		if let primary = touchReport.primary {
			updateTouchpad(
				x: Float(primary.position.x),
				y: Float(primary.position.y),
				isTouching: true
			)
		} else {
			updateTouchpad(x: 0, y: 0, isTouching: false)
		}

		if let secondary = touchReport.secondary {
			updateTouchpadSecondary(
				x: Float(secondary.position.x),
				y: Float(secondary.position.y),
				isTouching: true
			)
		} else {
			updateTouchpadSecondary(x: 0, y: 0, isTouching: false)
		}

		if touchReport.isTouching {
			scheduleAppleTVRemoteTouchRelease()
		} else {
			cancelAppleTVRemoteTouchRelease()
		}
	}

	nonisolated func handleAppleTVRemoteMultitouch(x: Float, y: Float, isTouching: Bool) {
		storage.lock.lock()
		storage.lastInputTime = CFAbsoluteTimeGetCurrent()
		storage.lock.unlock()

		if isTouching {
			updateTouchpad(x: x, y: y, isTouching: true)
			updateTouchpadSecondary(x: 0, y: 0, isTouching: false)
			scheduleAppleTVRemoteTouchRelease()
		} else {
			releaseAppleTVRemoteTouchIfStillActive()
		}
	}

	nonisolated static func appleTVRemoteTouchReport(
		reportID: UInt32,
		report: UnsafePointer<UInt8>,
		length: Int
	) -> AppleTVRemoteTouchReport? {
		guard length > 0 else { return nil }

		let start = reportID == 0xFF && report[0] == 0xFF ? 1 : 0
		let available = length - start
		guard available > 0 else { return nil }

		if available == AppleTVRemoteHID.firstGenerationOneFingerTouchReportLength,
		   report[start + 2] == AppleTVRemoteHID.firstGenerationTouchEventMarker {
			let fingerCount = Int(report[start])
			return AppleTVRemoteTouchReport(
				primary: fingerCount >= 1 ? appleTVRemoteTouchPoint(bytes: report + start + 6, wrapsX: false) : nil,
				secondary: nil
			)
		}

		if available == AppleTVRemoteHID.firstGenerationTwoFingerTouchReportLength,
		   report[start + 2] == AppleTVRemoteHID.firstGenerationTouchEventMarker {
			let fingerCount = Int(report[start])
			return AppleTVRemoteTouchReport(
				primary: fingerCount >= 1 ? appleTVRemoteTouchPoint(bytes: report + start + 6, wrapsX: false) : nil,
				secondary: fingerCount >= 2 ? appleTVRemoteTouchPoint(bytes: report + start + 13, wrapsX: false) : nil
			)
		}

		if available >= AppleTVRemoteHID.currentRemoteTouchReportLength {
			return AppleTVRemoteTouchReport(
				primary: appleTVRemoteTouchPoint(bytes: report + start + 4, wrapsX: true),
				secondary: nil
			)
		}

		return nil
	}

		nonisolated func releaseAppleTVRemoteButtonsIfNeeded() {
			storage.lock.lock()
			storage.appleTVRemoteActiveSystemKeyTypes.removeAll()
			storage.appleTVRemoteSystemKeyTypeSuppressUntil.removeAll()
			storage.lock.unlock()

			for button in ControllerButton.appleTVRemoteButtons {
				handleButton(button, pressed: false)
			}
		}

	nonisolated func releaseAppleTVRemoteTouchIfStillActive() {
		storage.lock.lock()
		storage.appleTVRemoteTouchReleaseWorkItem?.cancel()
		storage.appleTVRemoteTouchReleaseWorkItem = nil
		let primaryActive = storage.isTouchpadTouching
		let secondaryActive = storage.isTouchpadSecondaryTouching
		storage.lock.unlock()

		if secondaryActive {
			updateTouchpadSecondary(x: 0, y: 0, isTouching: false)
		}
		if primaryActive {
			updateTouchpad(x: 0, y: 0, isTouching: false)
		}
	}

	private nonisolated func scheduleAppleTVRemoteTouchRelease() {
		let workItem = DispatchWorkItem { [weak self] in
			self?.releaseAppleTVRemoteTouchIfStillActive()
		}

		storage.lock.lock()
		storage.appleTVRemoteTouchReleaseWorkItem?.cancel()
		storage.appleTVRemoteTouchReleaseWorkItem = workItem
		storage.lock.unlock()

		controllerQueue.asyncAfter(
			deadline: .now() + AppleTVRemoteHID.touchReleaseDelay,
			execute: workItem
		)
	}

	private nonisolated func cancelAppleTVRemoteTouchRelease() {
		storage.lock.lock()
		storage.appleTVRemoteTouchReleaseWorkItem?.cancel()
		storage.appleTVRemoteTouchReleaseWorkItem = nil
		storage.lock.unlock()
	}

	private nonisolated static func appleTVRemoteTouchPoint(
		bytes: UnsafePointer<UInt8>,
		wrapsX: Bool
	) -> AppleTVRemoteTouchPoint? {
		let pressure = bytes[5]
		guard pressure > 0 else { return nil }

		let rawX = Int(bytes[0]) + 255 * Int(bytes[1] & 0x07)
		var x = CGFloat(rawX - 230) / 15.0
		if wrapsX, x < 0 {
			x += AppleTVRemoteHID.touchMaxX
		}
		x = min(max(x, 0), AppleTVRemoteHID.touchMaxX)

		let rawYByte = bytes[2]
		let yValue = rawYByte & 0x80 != 0
			? Int(rawYByte) - 188
			: Int(rawYByte) + 255 - 188
		let y = min(max(CGFloat(yValue), 0), AppleTVRemoteHID.touchMaxY)

		return AppleTVRemoteTouchPoint(
			position: CGPoint(
				x: normalizedAppleTVRemoteTouchCoordinate(x, maxValue: AppleTVRemoteHID.touchMaxX),
				y: normalizedAppleTVRemoteTouchCoordinate(y, maxValue: AppleTVRemoteHID.touchMaxY)
			),
			pressure: pressure
		)
	}

	private nonisolated static func normalizedAppleTVRemoteTouchCoordinate(
		_ value: CGFloat,
		maxValue: CGFloat
	) -> CGFloat {
		guard maxValue > 0 else { return 0 }
		return (value / maxValue) * 2.0 - 1.0
	}

	private static func appleTVRemoteButtonHIDMatchingCriteria() -> CFArray {
		appleTVRemoteBluetoothMatchingCriteria(usagePage: AppleTVRemoteHID.consumerUsagePage)
	}

	private static func appleTVRemoteTouchHIDMatchingCriteria() -> CFArray {
		appleTVRemoteBluetoothMatchingCriteria(usagePage: AppleTVRemoteHID.digitizerUsagePage)
	}

	private static func appleTVRemoteBluetoothMatchingCriteria(usagePage: UInt32) -> CFArray {
		let bluetoothRemotes = AppleTVRemoteHID.knownBluetoothRemoteProductIDs.map { productID in
			[
				kIOHIDVendorIDKey as String: AppleTVRemoteHID.appleBluetoothCompanyID,
				kIOHIDProductIDKey as String: productID,
				kIOHIDDeviceUsagePageKey as String: usagePage,
			] as CFDictionary
		}
		return bluetoothRemotes as CFArray
	}

	private func activateAppleTVRemoteHIDSessionIfNeeded(_ device: IOHIDDevice) {
		guard connectedController == nil else { return }

		genericHIDFallbackTimer?.cancel()
		genericHIDFallbackTimer = nil
		if genericHIDController != nil {
			genericHIDController?.stop()
			genericHIDController = nil
			isGenericController = false
		}

		storage.lock.lock()
		storage.isAppleTVRemote = true
		storage.isDualSense = false
		storage.isDualSenseEdge = false
		storage.isDualShock = false
		storage.isNintendo = false
		storage.isXboxElite = false
		storage.isJoyConLeft = false
		storage.isJoyConRight = false
		storage.isSteamController = false
		storage.lock.unlock()

		UserDefaults.standard.set(true, forKey: Config.lastControllerWasAppleTVRemoteKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)

		currentControllerIdentity = ControllerIdentityResolver.identity(for: device, fallbackName: "Apple TV Remote")
		controllerName = "Apple TV Remote"
		isGenericController = false
		isConnected = true
		startDisplayUpdateTimer()
	}

	nonisolated private static func isAppleTVRemoteHIDDevice(_ device: IOHIDDevice) -> Bool {
		guard isAppleTVRemoteBaseHIDDevice(device) else { return false }

		let primaryUsagePage = IOHIDDeviceGetProperty(device, "PrimaryUsagePage" as CFString) as? Int
		return primaryUsagePage == Int(AppleTVRemoteHID.consumerUsagePage)
	}

	nonisolated private static func isAppleTVRemoteTouchHIDDevice(_ device: IOHIDDevice) -> Bool {
		guard isAppleTVRemoteBaseHIDDevice(device) else { return false }

		let primaryUsagePage = IOHIDDeviceGetProperty(device, "PrimaryUsagePage" as CFString) as? Int
		let primaryUsage = IOHIDDeviceGetProperty(device, "PrimaryUsage" as CFString) as? Int
		return primaryUsagePage == Int(AppleTVRemoteHID.digitizerUsagePage)
			&& primaryUsage == Int(AppleTVRemoteHID.digitizerUsage)
	}

	nonisolated private static func isAppleTVRemoteBaseHIDDevice(_ device: IOHIDDevice) -> Bool {
		let vendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int
		let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int

		let productName = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "").lowercased()
		let manufacturer = (IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? "").lowercased()
		let bundleID = (IOHIDDeviceGetProperty(device, kCFBundleIdentifierKey as CFString) as? String ?? "").lowercased()
		let kernelBundleID = (IOHIDDeviceGetProperty(device, "CFBundleIdentifierKernel" as CFString) as? String ?? "").lowercased()
		let combined = "\(manufacturer) \(productName)"

		let isAppleVendorRemote = vendorID == AppleTVRemoteHID.appleVendorID
			&& (combined.contains("siri remote")
			|| combined.contains("apple tv remote")
			|| (manufacturer.contains("apple") && productName.contains("remote")))
		let isBluetoothRemote = vendorID == AppleTVRemoteHID.appleBluetoothCompanyID
			&& productID.map(AppleTVRemoteHID.knownBluetoothRemoteProductIDs.contains) == true
		let isAppleBluetoothRemoteService = IOHIDDeviceGetProperty(device, "AppleBluetoothRemote" as CFString) as? Bool == true
			|| bundleID.contains("applebluetoothremote")
			|| kernelBundleID.contains("applebluetoothremote")
		return isAppleVendorRemote || isBluetoothRemote || isAppleBluetoothRemoteService
	}

	nonisolated private static func appleTVRemoteHIDDeviceName(_ device: IOHIDDevice) -> String {
		let productName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
		let manufacturer = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String
		return [manufacturer, productName]
			.compactMap { $0 }
			.filter { !$0.isEmpty }
			.joined(separator: " ")
	}
}

private nonisolated func appleTVRemoteHIDDeviceMatchedCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	device: IOHIDDevice
) {
	guard let context else { return }
	let holder = Unmanaged<AppleTVRemoteHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
	guard let service = holder.service else { return }
	DispatchQueue.main.async {
		service.appleTVRemoteHIDDeviceAppeared(device)
	}
}

private nonisolated func appleTVRemoteHIDDeviceRemovedCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	device: IOHIDDevice
) {
	guard let context else { return }
	let holder = Unmanaged<AppleTVRemoteHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
	guard let service = holder.service else { return }
	DispatchQueue.main.async {
		service.appleTVRemoteHIDDeviceRemoved(device)
	}
}

private nonisolated func appleTVRemoteHIDInputValueCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	value: IOHIDValue
) {
	guard let context else { return }
	let holder = Unmanaged<AppleTVRemoteHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
	holder.service?.handleAppleTVRemoteHIDValue(value)
}

private nonisolated func appleTVRemoteHIDInputReportCallback(
	context: UnsafeMutableRawPointer?,
	result: IOReturn,
	sender: UnsafeMutableRawPointer?,
	type: IOHIDReportType,
	reportID: UInt32,
	report: UnsafeMutablePointer<UInt8>,
	reportLength: CFIndex
) {
	guard let context else { return }
	let holder = Unmanaged<AppleTVRemoteHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
	holder.service?.handleAppleTVRemoteTouchReport(
		reportID: reportID,
		report: UnsafePointer(report),
		length: Int(reportLength)
	)
}

private nonisolated func appleTVRemoteMultitouchCallback(
	context: UnsafeMutableRawPointer?,
	x: Float,
	y: Float,
	touching: Bool
) {
	guard let context else { return }
	let holder = Unmanaged<AppleTVRemoteHIDCallbackContext>.fromOpaque(context).takeUnretainedValue()
	holder.service?.handleAppleTVRemoteMultitouch(x: x, y: y, isTouching: touching)
}

private nonisolated func appleTVRemoteSystemEventTapCallback(
	proxy: CGEventTapProxy,
	type: CGEventType,
	event: CGEvent,
	userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
	guard let userInfo else {
		return Unmanaged.passUnretained(event)
	}

	if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
		let holder = Unmanaged<AppleTVRemoteSystemEventTapContext>.fromOpaque(userInfo).takeUnretainedValue()
		holder.service?.reenableAppleTVRemoteSystemEventSuppressionIfNeeded()
		return Unmanaged.passUnretained(event)
	}

	let holder = Unmanaged<AppleTVRemoteSystemEventTapContext>.fromOpaque(userInfo).takeUnretainedValue()
	if holder.service?.shouldSuppressAppleTVRemoteSystemEvent(event, type: type) == true {
		return nil
	}

	return Unmanaged.passUnretained(event)
}
