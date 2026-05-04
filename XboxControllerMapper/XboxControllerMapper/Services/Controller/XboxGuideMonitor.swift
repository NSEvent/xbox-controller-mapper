import Foundation
import IOKit.hid

func guideLog(_ message: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".controllerkeys_guide_debug.log")
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(message)\n"
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
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
    private(set) var isStarted = false

    // Paddle state tracking (Consumer Page 0x81 bitmask)
    private var paddleState: [Int: Bool] = [1: false, 2: false, 3: false, 4: false]
    // Consumer 0x81 bitmask mapping: bit -> paddle index
    // Matches GCXboxGamepad convention: P1=upper left, P2=upper right, P3=lower left, P4=lower right
    //   bit 2 = P1 (upper left), bit 0 = P2 (upper right)
    //   bit 3 = P3 (lower left), bit 1 = P4 (lower right)
    private static let paddleBitMapping: [(bit: Int, paddle: Int)] = [
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

    /// Tracks devices where Button Page usage 13 is a paddle (not Guide).
    /// On USB-style Elite 2 descriptors (>15 Button Page usages), usage 13 is a paddle
    /// and Guide is at usage 17. On BLE-style descriptors (15 usages), usage 13 IS Guide.
    private var devicesWhereUsage13IsPaddle = Set<UnsafeMutableRawPointer>()

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

        let retainedContext = Unmanaged.passRetained(CallbackContext(monitor: self)).toOpaque()
        callbackContext = retainedContext
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, Self.deviceMatchedCallback, retainedContext)
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, Self.deviceRemovedCallback, retainedContext)
        IOHIDManagerRegisterInputValueCallback(hidManager, Self.inputValueCallback, retainedContext)

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

        if let callbackContext {
            Unmanaged<CallbackContext>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }

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

            // Determine if usage 13 is Guide or a paddle on this device.
            // USB-style Elite 2 descriptors have >15 Button Page usages (buttons + paddles),
            // where usage 13 is a paddle and Guide is at usage 17.
            // BLE-style descriptors have exactly 15 Button Page usages, where usage 13 IS Guide.
            let maxButtonUsage = Self.maxButtonPageUsage(for: device)
            guideLog("  maxButtonUsage=\(maxButtonUsage)")
            if maxButtonUsage > 15 {
                let ptr = Unmanaged.passUnretained(device).toOpaque()
                devicesWhereUsage13IsPaddle.insert(ptr)
                guideLog("  usage 13 = paddle (USB-style descriptor), Guide at usage 17")
            }
        }
    }

    /// Returns the highest Button Page usage on a device by enumerating its HID elements.
    private static func maxButtonPageUsage(for device: IOHIDDevice) -> UInt32 {
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
            return 0
        }
        var maxUsage: UInt32 = 0
        for element in elements {
            if IOHIDElementGetUsagePage(element) == kHIDPage_Button {
                let usage = IOHIDElementGetUsage(element)
                if usage > maxUsage { maxUsage = usage }
            }
        }
        return maxUsage
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        guideLog("Device removed: \"\(getDeviceName(device))\"")

        let vid = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        if vid == 0x045E, let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int {
            connectedMicrosoftPIDs.remove(pid)
        }
        devicesWhereUsage13IsPaddle.remove(Unmanaged.passUnretained(device).toOpaque())
    }

    // MARK: - Input Value Handler

    fileprivate func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        // Guide button: Button Page
        // - Usage 17: Guide on USB and Classic BT controllers (>15 buttons on Button Page)
        // - Usage 13: Guide on BLE controllers (exactly 15 buttons on Button Page)
        //   BUT on USB-style Elite 2 descriptors, usage 13 is a PADDLE — skip it.
        if usagePage == kHIDPage_Button {
            if usage == 17 {
                let isPressed = intValue != 0
                DispatchQueue.main.async { [weak self] in
                    self?.onGuideButtonAction?(isPressed)
                }
            } else if usage == 13 {
                let device = IOHIDElementGetDevice(element)
                let ptr = Unmanaged.passUnretained(device).toOpaque()
                if !devicesWhereUsage13IsPaddle.contains(ptr) {
                    let isPressed = intValue != 0
                    DispatchQueue.main.async { [weak self] in
                        self?.onGuideButtonAction?(isPressed)
                    }
                }
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
