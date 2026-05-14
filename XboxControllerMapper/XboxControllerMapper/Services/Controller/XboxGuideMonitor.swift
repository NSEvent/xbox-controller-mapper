import Foundation
import IOKit.hid

func guideLog(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".controllerkeys_guide_debug.log")
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        try? AtomicFileWriter.write(line, to: url)
    }
}

/// Low-level HID monitor specifically to capture the Xbox Guide/Home button
/// which is often swallowed by the macOS GameController framework.
///
/// Uses IOHIDManager input value callbacks with VID-based matching to catch all Microsoft
/// controller interfaces. Automatically detects the HID descriptor variant (BLE vs USB/Classic BT)
/// to determine whether Button Page usage 13 is the Guide button or a paddle.
class XboxGuideMonitor {

    private var hidManager: IOHIDManager?
    private var callbackContext: UnsafeMutableRawPointer?
	private var callbackContextHolder: CallbackContext?
    private(set) var isStarted = false
	private let enableHardwareMonitoring: Bool

    // Paddle state tracking (Consumer Page 0x81 bitmask)
    private var paddleState: [Int: Bool] = [1: false, 2: false, 3: false, 4: false]
	// Consumer 0x81 bitmask mapping: bit -> paddle index.
	// Matches GCXboxGamepad convention: P1=upper left, P2=upper right, P3=lower left, P4=lower right.
	static let paddleBitMapping: [(bit: Int, paddle: Int)] = [
        (2, 1), (0, 2), (3, 3), (1, 4)
    ]

    /// Known Xbox Elite Series 2 product IDs (Microsoft VID 0x045E).
    /// The same hardware (Model 1797) reports different PIDs depending on
    /// connection type and firmware version:
    static let eliteSeries2PIDs: Set<Int> = [
        0x0B00,  // Elite 2 (USB)
        0x0B02,  // Elite 2 Core
        0x0B05,  // Elite 2 (Classic Bluetooth — old firmware, BR/EDR)
        0x0B22,  // Elite 2 (Bluetooth Low Energy — new firmware 5.x+)
    ]

	/// Devices whose HID traits have already been inspected.
	private var devicesWithKnownGuideTraits = Set<UnsafeMutableRawPointer>()

	/// Tracks devices with >15 Button Page usages (USB-style/Classic BT descriptors).
	/// On these devices, Button Page usage 13 is a paddle, not Guide.
	private var devicesWithExtendedButtons = Set<UnsafeMutableRawPointer>()

	/// Tracks devices that expose Consumer Page AC Home (0x0223) as Guide.
	/// On these devices, Button Page usage 17 can be a normal mirrored face button.
	private var devicesWithACHome = Set<UnsafeMutableRawPointer>()

    /// Product IDs of currently connected Microsoft controller devices.
    /// Updated on device match/removal. Thread-safe via main queue (HID callbacks run on main).
    private(set) var connectedMicrosoftPIDs: Set<Int> = []

    /// Whether any connected Microsoft controller is an Xbox Elite Series 2.
    var isEliteControllerConnected: Bool {
        !connectedMicrosoftPIDs.isDisjoint(with: Self.eliteSeries2PIDs)
    }

    // Callbacks to main controller service
    var onGuideButtonAction: ((Bool) -> Void)?
    /// Paddle callback: (paddleIndex 1-4, pressed)
    var onPaddleAction: ((Int, Bool) -> Void)?

    private final class CallbackContext {
        weak var monitor: XboxGuideMonitor?
        init(monitor: XboxGuideMonitor) { self.monitor = monitor }
		// Avoid inferred MainActor-isolated teardown for this unmanaged HID callback holder.
		nonisolated deinit { }
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

	private func prepareCallbackContext() -> UnsafeMutableRawPointer {
		if let callbackContext {
			return callbackContext
		}
		let holder = CallbackContext(monitor: self)
		callbackContextHolder = holder
		let context = Unmanaged.passUnretained(holder).toOpaque()
		callbackContext = context
		return context
	}

	var hasCallbackContextForTesting: Bool {
		callbackContext != nil
	}

	func prepareCallbackContextForTesting() {
		_ = prepareCallbackContext()
	}

    // MARK: - Lifecycle

	init(enableHardwareMonitoring: Bool = true) {
		self.enableHardwareMonitoring = enableHardwareMonitoring
        start()
    }

    deinit {
        stop()
    }

    func start() {
        guard !isStarted else { return }

		guard enableHardwareMonitoring else {
			isStarted = true
			return
		}

        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let hidManager = hidManager else { return }

        // Match broadly: gamepads, joysticks, AND Microsoft VID directly
        let gamepadMatching = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad
        ] as CFDictionary

        let joystickMatching = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick
        ] as CFDictionary

        // Also match by Microsoft VID to catch any interface the framework might not claim
        let microsoftMatching = [
            kIOHIDVendorIDKey: 0x045E
        ] as CFDictionary

        let criteria = [gamepadMatching, joystickMatching, microsoftMatching] as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(hidManager, criteria)

		let context = prepareCallbackContext()
		IOHIDManagerRegisterDeviceMatchingCallback(hidManager, Self.deviceMatchedCallback, context)
		IOHIDManagerRegisterDeviceRemovalCallback(hidManager, Self.deviceRemovedCallback, context)
		IOHIDManagerRegisterInputValueCallback(hidManager, Self.inputValueCallback, context)

        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
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

		callbackContext = nil
		callbackContextHolder = nil

        isStarted = false
    }

    // MARK: - Device Handlers

    fileprivate func deviceMatched(_ device: IOHIDDevice) {
        let name = getDeviceName(device)
        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        guideLog("Device matched: \"\(name)\" VID=0x\(String(vid, radix: 16)) PID=0x\(String(pid, radix: 16))")

        if vid == 0x045E {
            connectedMicrosoftPIDs.insert(pid)

			cacheGuideTraits(for: device, shouldLog: true)
        }
    }

	private struct GuideTraits {
		let hasExtendedButtons: Bool
		let hasACHome: Bool
	}

	/// Returns the HID guide routing traits for a device by enumerating its elements.
	private static func guideTraits(for device: IOHIDDevice) -> GuideTraits {
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
			return GuideTraits(hasExtendedButtons: false, hasACHome: false)
        }
        var maxUsage: UInt32 = 0
		var hasACHome = false
        for element in elements {
			let usagePage = IOHIDElementGetUsagePage(element)
			if usagePage == kHIDPage_Button {
                let usage = IOHIDElementGetUsage(element)
                if usage > maxUsage { maxUsage = usage }
			} else if usagePage == kHIDPage_Consumer && IOHIDElementGetUsage(element) == 0x0223 {
				hasACHome = true
			}
		}
		return GuideTraits(hasExtendedButtons: maxUsage > 15, hasACHome: hasACHome)
	}

	/// Pure guide-event routing policy. Kept testable because Elite 2 HID descriptors vary by firmware.
	static func isGuideEvent(
		usagePage: UInt32,
		usage: UInt32,
		hasExtendedButtons: Bool,
		hasACHome: Bool
	) -> Bool {
		if usagePage == UInt32(kHIDPage_Consumer) && usage == 0x0223 {
			return true
		}

		guard usagePage == UInt32(kHIDPage_Button) else { return false }

		if usage == 13 {
			return !hasExtendedButtons
		}
		if usage == 17 {
			return !hasACHome
		}
		return false
	}

	@discardableResult
	private func cacheGuideTraits(for device: IOHIDDevice, shouldLog: Bool = false) -> GuideTraits {
		let ptr = Unmanaged.passUnretained(device).toOpaque()
		if !devicesWithKnownGuideTraits.contains(ptr) {
			let traits = Self.guideTraits(for: device)
			devicesWithKnownGuideTraits.insert(ptr)
			if traits.hasExtendedButtons {
				devicesWithExtendedButtons.insert(ptr)
			}
			if traits.hasACHome {
				devicesWithACHome.insert(ptr)
			}
			if shouldLog {
				guideLog("  hasExtendedButtons=\(traits.hasExtendedButtons) hasACHome=\(traits.hasACHome)")
				if traits.hasExtendedButtons {
					guideLog("  usage 13 = paddle (extended button descriptor)")
				}
				if traits.hasACHome {
					guideLog("  Guide = Consumer Page AC Home (0x0223)")
				}
            }
        }
		return GuideTraits(
			hasExtendedButtons: devicesWithExtendedButtons.contains(ptr),
			hasACHome: devicesWithACHome.contains(ptr)
		)
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        guideLog("Device removed: \"\(getDeviceName(device))\"")

        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        if vid == 0x045E, let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int {
            connectedMicrosoftPIDs.remove(pid)
        }
		let ptr = Unmanaged.passUnretained(device).toOpaque()
		devicesWithKnownGuideTraits.remove(ptr)
		devicesWithExtendedButtons.remove(ptr)
		devicesWithACHome.remove(ptr)
    }

    // MARK: - Input Value Handler

    fileprivate func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

		let device = IOHIDElementGetDevice(element)
		let traits = cacheGuideTraits(for: device)
		if Self.isGuideEvent(
			usagePage: usagePage,
			usage: usage,
			hasExtendedButtons: traits.hasExtendedButtons,
			hasACHome: traits.hasACHome
		) {
			let isPressed = intValue != 0
			DispatchQueue.main.async { [weak self] in
				self?.onGuideButtonAction?(isPressed)
            }
        }

        // Elite Series 2 paddles: Consumer Page, usage 0x81 (4-bit bitmask)
        if usagePage == kHIDPage_Consumer && usage == 0x81 {
            let mask = intValue
            for (bit, paddle) in Self.paddleBitMapping {
                let pressed = (mask & (1 << bit)) != 0
                if pressed != paddleState[paddle] {
                    paddleState[paddle] = pressed
                    DispatchQueue.main.async { [weak self] in
                        self?.onPaddleAction?(paddle, pressed)
                    }
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
