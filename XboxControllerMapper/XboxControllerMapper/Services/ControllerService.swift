import Foundation
import GameController
import Combine
import CoreHaptics
import IOKit
import IOKit.hid

// MARK: - DualSense HID Constants

private enum DualSenseHIDConstants {
    // Report IDs
    static let usbOutputReportID: UInt8 = 0x02
    static let bluetoothOutputReportID: UInt8 = 0x31

    // Report sizes
    static let usbReportSize = 64
    static let bluetoothReportSize = 78

    // Common byte offsets (0-indexed within common data section)
    static let validFlag0Offset = 0
    static let validFlag1Offset = 1
    static let muteButtonLEDOffset = 8
    static let validFlag2Offset = 38
    static let lightbarSetupOffset = 41
    static let ledBrightnessOffset = 42
    static let playerLEDsOffset = 43
    static let lightbarRedOffset = 44
    static let lightbarGreenOffset = 45
    static let lightbarBlueOffset = 46

    // Valid flag bits
    static let validFlag1MuteLED: UInt8 = 0x01
    static let validFlag1Lightbar: UInt8 = 0x04
    static let validFlag1PlayerLEDs: UInt8 = 0x10
    static let validFlag2LightbarSetup: UInt8 = 0x02

    // Lightbar setup value
    static let lightbarSetupEnable: UInt8 = 0x01
}

// MARK: - Thread-Safe Input State (High Performance)

private final class ControllerStorage: @unchecked Sendable {
    let lock = NSLock()
    var leftStick: CGPoint = .zero
    var rightStick: CGPoint = .zero
    var leftTrigger: Float = 0
    var rightTrigger: Float = 0

    // Touchpad State (DualSense only)
    var touchpadPosition: CGPoint = .zero
    var touchpadPreviousPosition: CGPoint = .zero
    var touchpadSecondaryPosition: CGPoint = .zero
    var touchpadSecondaryPreviousPosition: CGPoint = .zero
    var isTouchpadTouching: Bool = false
    var isTouchpadSecondaryTouching: Bool = false
    var touchpadSecondaryLastUpdate: TimeInterval = 0
    var touchpadSecondaryLastTouchTime: TimeInterval = 0
    var isDualSense: Bool = false
    var isBluetoothConnection: Bool = false
    var currentLEDSettings: DualSenseLEDSettings?
    var pendingTouchpadDelta: CGPoint? = nil  // Delayed by 1 frame to filter lift artifacts
    var touchpadFramesSinceTouch: Int = 0  // Skip first frames after touch to let position settle
    var touchpadSecondaryFramesSinceTouch: Int = 0
    var touchpadClickArmed: Bool = false
    var touchpadClickStartPosition: CGPoint = .zero
    var touchpadMovementBlocked: Bool = false
    var touchpadTouchStartTime: TimeInterval = 0  // Time when finger first touched
    var touchpadTouchStartPosition: CGPoint = .zero  // Position when finger first touched
    var touchpadDebugLastLogTime: TimeInterval = 0

    // Button State
    var activeButtons: Set<ControllerButton> = []
    var buttonPressTimestamps: [ControllerButton: Date] = [:]
    var lastMicButtonState: Bool = false

    // Chord Detection State
    var pendingButtons: Set<ControllerButton> = []
    var capturedButtonsInWindow: Set<ControllerButton> = []
    var pendingReleases: [ControllerButton: TimeInterval] = [:]
    var chordWorkItem: DispatchWorkItem?
    var chordWindow: TimeInterval = 0.15

    // Callbacks
    var onButtonPressed: ((ControllerButton) -> Void)?
    var onButtonReleased: ((ControllerButton, TimeInterval) -> Void)?
    var onChordDetected: ((Set<ControllerButton>) -> Void)?
    var onLeftStickMoved: ((CGPoint) -> Void)?
    var onRightStickMoved: ((CGPoint) -> Void)?
    var onTouchpadMoved: ((CGPoint) -> Void)?  // Delta movement
    var onTouchpadGesture: ((TouchpadGesture) -> Void)?
}

/// Service for managing Xbox controller connection and input
@MainActor
class ControllerService: ObservableObject {
    @Published var isConnected = false
    @Published var connectedController: GCController?
    @Published var controllerName: String = ""

    /// Currently pressed buttons (UI use only, updated asynchronously)
    @Published var activeButtons: Set<ControllerButton> = []
    
    private let controllerQueue = DispatchQueue(label: "com.xboxmapper.controller", qos: .userInteractive)
    private let storage = ControllerStorage()

    // HID monitoring for DualSense mic button (not exposed by GameController framework)
    private var hidManager: IOHIDManager?
    private var hidReportBuffer: UnsafeMutablePointer<UInt8>?
    private var hidDevice: IOHIDDevice?
    
    nonisolated var threadSafeLeftStick: CGPoint {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.leftStick
    }
    
    nonisolated var threadSafeRightStick: CGPoint {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.rightStick
    }
    
    nonisolated var threadSafeLeftTrigger: Float {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.leftTrigger
    }
    
    nonisolated var threadSafeRightTrigger: Float {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.rightTrigger
    }
    
    // Accessor for MappingEngine to check active buttons thread-safely
    nonisolated var threadSafeActiveButtons: Set<ControllerButton> {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.activeButtons
    }

    // Touchpad accessors (DualSense only)
    nonisolated var threadSafeTouchpadDelta: CGPoint {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        guard storage.isTouchpadTouching else { return .zero }
        let delta = CGPoint(
            x: storage.touchpadPosition.x - storage.touchpadPreviousPosition.x,
            y: storage.touchpadPosition.y - storage.touchpadPreviousPosition.y
        )
        return delta
    }

    nonisolated var threadSafeIsTouchpadTouching: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isTouchpadTouching
    }

    nonisolated var threadSafeIsTouchpadMovementBlocked: Bool {
        let now = CFAbsoluteTimeGetCurrent()
        storage.lock.lock()
        let blocked = storage.touchpadMovementBlocked ||
            (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
        storage.lock.unlock()
        return blocked
    }

    nonisolated var threadSafeIsDualSense: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isDualSense
    }

    nonisolated var threadSafeLEDSettings: DualSenseLEDSettings? {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.currentLEDSettings
    }

    /// Left joystick position (-1 to 1) - UI/Legacy use only
    @Published var leftStick: CGPoint = .zero

    /// Right joystick position (-1 to 1) - UI/Legacy use only
    @Published var rightStick: CGPoint = .zero

    /// Left trigger pressure (0 to 1) - UI/Legacy use only
    @Published var leftTriggerValue: Float = 0

    /// Right trigger pressure (0 to 1) - UI/Legacy use only
    @Published var rightTriggerValue: Float = 0

    /// Chord detection window (accessible for testing and configuration)
    var chordWindow: TimeInterval {
        get {
            storage.lock.lock()
            defer { storage.lock.unlock() }
            return storage.chordWindow
        }
        set {
            storage.lock.lock()
            storage.chordWindow = newValue
            storage.lock.unlock()
        }
    }

    // MARK: - Throttled UI Display Values (updated at ~15Hz to avoid UI blocking)
    @Published var displayLeftStick: CGPoint = .zero
    @Published var displayRightStick: CGPoint = .zero
    @Published var displayLeftTrigger: Float = 0
    @Published var displayRightTrigger: Float = 0
    @Published var displayTouchpadPosition: CGPoint = .zero
    @Published var displayTouchpadSecondaryPosition: CGPoint = .zero
    @Published var displayIsTouchpadTouching: Bool = false
    @Published var displayIsTouchpadSecondaryTouching: Bool = false
    private var displayUpdateTimer: DispatchSourceTimer?

    /// Battery level (0 to 1)
    @Published var batteryLevel: Float = -1
    
    /// Battery state
    @Published var batteryState: GCDeviceBattery.State = .unknown

    // Callback proxies (Thread-safe storage backing)
    var onButtonPressed: ((ControllerButton) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onButtonPressed }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onButtonPressed = newValue }
    }
    var onButtonReleased: ((ControllerButton, TimeInterval) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onButtonReleased }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onButtonReleased = newValue }
    }
    var onChordDetected: ((Set<ControllerButton>) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onChordDetected }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onChordDetected = newValue }
    }
    var onLeftStickMoved: ((CGPoint) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onLeftStickMoved }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onLeftStickMoved = newValue }
    }
    var onRightStickMoved: ((CGPoint) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onRightStickMoved }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onRightStickMoved = newValue }
    }
    var onTouchpadMoved: ((CGPoint) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onTouchpadMoved }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onTouchpadMoved = newValue }
    }
    var onTouchpadGesture: ((TouchpadGesture) -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onTouchpadGesture }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onTouchpadGesture = newValue }
    }

    private var cancellables = Set<AnyCancellable>()
    
    // Low-level monitor for Xbox Guide button
    private let guideMonitor = XboxGuideMonitor()
    
    // Low-level monitor for Battery (Bluetooth Workaround for macOS/Xbox issue)
    private let batteryMonitor = BluetoothBatteryMonitor()

    // Haptic engines for controller feedback (try multiple localities)
    private var hapticEngines: [CHHapticEngine] = []
    private let hapticQueue = DispatchQueue(label: "com.xboxmapper.haptic", qos: .userInitiated)

    init() {
        GCController.shouldMonitorBackgroundEvents = true

        setupNotifications()
        startDiscovery()
        checkConnectedControllers()
        
        guideMonitor.onGuideButtonAction = { [weak self] isPressed in
            guard let self = self else { return }
            self.controllerQueue.async {
                self.handleButton(.xbox, pressed: isPressed)
            }
        }
        
        batteryMonitor.startMonitoring()
        batteryMonitor.$batteryLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.updateBatteryInfo()
            }
            .store(in: &cancellables)
    }

    func cleanup() {
        stopDiscovery()
        batteryMonitor.stopMonitoring()
    }

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .GCControllerDidConnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let controller = notification.object as? GCController {
                    self?.controllerConnected(controller)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                if let controller = notification.object as? GCController,
                   controller == self?.connectedController {
                    self?.controllerDisconnected()
                }
            }
            .store(in: &cancellables)
    }

    private func startDiscovery() {
        GCController.startWirelessControllerDiscovery()
    }

    private func stopDiscovery() {
        GCController.stopWirelessControllerDiscovery()
    }

    private func checkConnectedControllers() {
        if let controller = GCController.controllers().first {
            controllerConnected(controller)
        }
    }

    private func controllerConnected(_ controller: GCController) {
        connectedController = controller
        isConnected = true
        controllerName = controller.vendorName ?? "Xbox Controller"

        setupInputHandlers(for: controller)
        setupHaptics(for: controller)
        updateBatteryInfo()
        startDisplayUpdateTimer()
    }

    private func controllerDisconnected() {
        connectedController = nil
        isConnected = false
        controllerName = ""
        activeButtons.removeAll()
        leftStick = .zero
        rightStick = .zero
        batteryLevel = -1
        batteryState = .unknown
        stopDisplayUpdateTimer()
        stopHaptics()
        cleanupHIDMonitoring()  // Clean up mic button monitoring

        storage.lock.lock()
        storage.activeButtons.removeAll()
        storage.buttonPressTimestamps.removeAll()
        storage.pendingButtons.removeAll()
        storage.capturedButtonsInWindow.removeAll()
        storage.pendingReleases.removeAll()
        storage.chordWorkItem?.cancel()
        storage.leftStick = .zero
        storage.rightStick = .zero
        // Reset DualSense state
        storage.isDualSense = false
        storage.isTouchpadTouching = false
        storage.touchpadPosition = .zero
        storage.touchpadPreviousPosition = .zero
        storage.pendingTouchpadDelta = nil
        storage.touchpadFramesSinceTouch = 0
        storage.lastMicButtonState = false
        storage.lock.unlock()
    }

    // MARK: - Display Update Timer

    private func startDisplayUpdateTimer() {
        stopDisplayUpdateTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: Config.displayRefreshInterval, leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            let tsLeft = self.threadSafeLeftStick
            let tsRight = self.threadSafeRightStick
            let tsLeftTrig = self.threadSafeLeftTrigger
            let tsRightTrig = self.threadSafeRightTrigger
            
            self.leftStick = tsLeft
            self.rightStick = tsRight
            self.leftTriggerValue = tsLeftTrig
            self.rightTriggerValue = tsRightTrig
            
            if abs(self.displayLeftStick.x - tsLeft.x) > Config.displayUpdateDeadzone ||
               abs(self.displayLeftStick.y - tsLeft.y) > Config.displayUpdateDeadzone {
                self.displayLeftStick = tsLeft
            }
            if abs(self.displayRightStick.x - tsRight.x) > Config.displayUpdateDeadzone ||
               abs(self.displayRightStick.y - tsRight.y) > Config.displayUpdateDeadzone {
                self.displayRightStick = tsRight
            }
            if abs(self.displayLeftTrigger - tsLeftTrig) > Float(Config.displayUpdateDeadzone) {
                self.displayLeftTrigger = tsLeftTrig
            }
            if abs(self.displayRightTrigger - tsRightTrig) > Float(Config.displayUpdateDeadzone) {
                self.displayRightTrigger = tsRightTrig
            }

            // Touchpad display updates
            self.storage.lock.lock()
            let touchPos = self.storage.touchpadPosition
            let touchSecPos = self.storage.touchpadSecondaryPosition
            let isTouching = self.storage.isTouchpadTouching
            let isSecTouching = self.storage.isTouchpadSecondaryTouching
            self.storage.lock.unlock()

            if self.displayTouchpadPosition != touchPos {
                self.displayTouchpadPosition = touchPos
            }
            if self.displayTouchpadSecondaryPosition != touchSecPos {
                self.displayTouchpadSecondaryPosition = touchSecPos
            }
            if self.displayIsTouchpadTouching != isTouching {
                self.displayIsTouchpadTouching = isTouching
            }
            if self.displayIsTouchpadSecondaryTouching != isSecTouching {
                self.displayIsTouchpadSecondaryTouching = isSecTouching
            }
        }
        timer.resume()
        displayUpdateTimer = timer
    }

    private func stopDisplayUpdateTimer() {
        displayUpdateTimer?.cancel()
        displayUpdateTimer = nil
        displayLeftStick = .zero
        displayRightStick = .zero
        displayLeftTrigger = 0
        displayRightTrigger = 0
        displayTouchpadPosition = .zero
        displayTouchpadSecondaryPosition = .zero
        displayIsTouchpadTouching = false
        displayIsTouchpadSecondaryTouching = false
    }

    private func updateBatteryInfo() {
        if let ioLevel = batteryMonitor.batteryLevel {
            batteryLevel = Float(ioLevel) / 100.0
            batteryState = batteryMonitor.isCharging ? .charging : .discharging
            return
        }
        
        if let battery = connectedController?.battery {
            batteryLevel = battery.batteryLevel
            batteryState = battery.batteryState
        }
        
        if isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.batteryUpdateInterval) { [weak self] in
                self?.updateBatteryInfo()
            }
        }
    }

    private func setupInputHandlers(for controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        // Use controllerQueue for all button inputs
        
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.a, pressed: pressed) }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.b, pressed: pressed) }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.x, pressed: pressed) }
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.y, pressed: pressed) }
        }

        // Bumpers
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.leftBumper, pressed: pressed) }
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.rightBumper, pressed: pressed) }
        }

        // Triggers
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            self?.updateLeftTrigger(value, pressed: pressed)
        }
        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            self?.updateRightTrigger(value, pressed: pressed)
        }

        // D-pad
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.dpadUp, pressed: pressed) }
        }
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.dpadDown, pressed: pressed) }
        }
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.dpadLeft, pressed: pressed) }
        }
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.dpadRight, pressed: pressed) }
        }

        // Special buttons
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.menu, pressed: pressed) }
        }
        gamepad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.view, pressed: pressed) }
        }
        
        if let extendedGamepad = gamepad as? GCExtendedGamepad {
            extendedGamepad.buttonHome?.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.controllerQueue.async { self?.handleButton(.xbox, pressed: pressed) }
            }
        }

        if let xboxGamepad = gamepad as? GCXboxGamepad {
            xboxGamepad.buttonShare?.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.controllerQueue.async { self?.handleButton(.share, pressed: pressed) }
            }
        }

        gamepad.leftThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.leftThumbstick, pressed: pressed) }
        }
        gamepad.rightThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(.rightThumbstick, pressed: pressed) }
        }

        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.updateLeftStick(x: xValue, y: yValue)
        }

        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            self?.updateRightStick(x: xValue, y: yValue)
        }

        // DualSense-specific: Touchpad support
        if let dualSenseGamepad = gamepad as? GCDualSenseGamepad {
            storage.lock.lock()
            storage.isDualSense = true
            storage.lock.unlock()

            // Touchpad button (click)
            dualSenseGamepad.touchpadButton.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.armTouchpadClick(pressed: pressed)
                self?.controllerQueue.async { self?.handleButton(.touchpadButton, pressed: pressed) }
            }

            // Touchpad primary finger position (for mouse control)
            // The touchpad provides X/Y from -1 to 1, we track position and calculate delta
            dualSenseGamepad.touchpadPrimary.valueChangedHandler = { [weak self] _, xValue, yValue in
                self?.updateTouchpad(x: xValue, y: yValue)
            }

            // Touchpad secondary finger position (for gestures)
            dualSenseGamepad.touchpadSecondary.valueChangedHandler = { [weak self] _, xValue, yValue in
                self?.updateTouchpadSecondary(x: xValue, y: yValue)
            }

            // Set up HID monitoring for mic button (not exposed by GameController framework)
            setupMicButtonMonitoring()
        }
    }

    // MARK: - DualSense Mic Button Monitoring (via IOKit HID)

    private func setupMicButtonMonitoring() {
        // Clean up any existing HID manager
        cleanupHIDMonitoring()

        // Allocate report buffer (must persist for callbacks)
        hidReportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 100)

        // Create HID manager
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        guard let manager = hidManager else { return }

        // Match DualSense controller
        let matchingDict: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x054C,  // Sony
            kIOHIDProductIDKey as String: 0x0CE6, // DualSense
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        // Schedule with run loop first
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // Get connected devices and set up input report callback on each
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices {
                setupHIDDeviceCallback(device)
            }
        }
    }

    private func setupHIDDeviceCallback(_ device: IOHIDDevice) {
        hidDevice = device
        detectConnectionType(device: device)
        guard let buffer = hidReportBuffer else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 100, { context, result, sender, type, reportID, report, reportLength in
            guard let context = context else { return }
            let service = Unmanaged<ControllerService>.fromOpaque(context).takeUnretainedValue()
            service.handleHIDReport(reportID: reportID, report: report, length: Int(reportLength))
        }, context)

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    private func cleanupHIDMonitoring() {
        if let device = hidDevice {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        hidDevice = nil

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        hidManager = nil

        if let buffer = hidReportBuffer {
            buffer.deallocate()
        }
        hidReportBuffer = nil
    }

    // MARK: - DualSense LED Control

    private func detectConnectionType(device: IOHIDDevice) {
        if let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String {
            storage.lock.lock()
            storage.isBluetoothConnection = (transport.lowercased() == "bluetooth")
            storage.lock.unlock()
        }
    }

    /// Applies LED settings to the connected DualSense controller
    func applyLEDSettings(_ settings: DualSenseLEDSettings) {
        storage.lock.lock()
        let isDualSense = storage.isDualSense
        let isBluetooth = storage.isBluetoothConnection
        storage.currentLEDSettings = settings
        storage.lock.unlock()

        guard isDualSense, let device = hidDevice else { return }

        if isBluetooth {
            sendBluetoothOutputReport(device: device, settings: settings)
        } else {
            sendUSBOutputReport(device: device, settings: settings)
        }
    }

    private func sendUSBOutputReport(device: IOHIDDevice, settings: DualSenseLEDSettings) {
        var report = [UInt8](repeating: 0, count: DualSenseHIDConstants.usbReportSize)

        // Report ID
        report[0] = DualSenseHIDConstants.usbOutputReportID

        // Valid flags - pydualsense uses 0xFF for flag0 and 0x57 for flag1
        let dataOffset = 1
        report[dataOffset + 0] = 0xFF  // flag0: enable all
        report[dataOffset + 1] = 0x57  // flag1: 0x01|0x02|0x04|0x10|0x40 (LED strips, mic, player LEDs)

        // Mute button LED (byte 9)
        report[dataOffset + DualSenseHIDConstants.muteButtonLEDOffset] = settings.muteButtonLED.byteValue

        // LED brightness (byte 43)
        report[dataOffset + DualSenseHIDConstants.ledBrightnessOffset] = settings.lightBarBrightness.byteValue

        // Player LEDs (byte 44)
        report[dataOffset + DualSenseHIDConstants.playerLEDsOffset] = settings.playerLEDs.bitmask

        // Light bar color (bytes 45, 46, 47)
        report[dataOffset + DualSenseHIDConstants.lightbarRedOffset] = settings.lightBarColor.redByte
        report[dataOffset + DualSenseHIDConstants.lightbarGreenOffset] = settings.lightBarColor.greenByte
        report[dataOffset + DualSenseHIDConstants.lightbarBlueOffset] = settings.lightBarColor.blueByte

        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualSenseHIDConstants.usbOutputReportID),
            report,
            report.count
        )

        if result != kIOReturnSuccess {
            print("Failed to send USB LED report: \(result)")
        }
    }

    private func sendBluetoothOutputReport(device: IOHIDDevice, settings: DualSenseLEDSettings) {
        var report = [UInt8](repeating: 0, count: DualSenseHIDConstants.bluetoothReportSize)

        // Report ID
        report[0] = DualSenseHIDConstants.bluetoothOutputReportID

        // Bluetooth header
        report[1] = 0x02
        report[2] = 0x00
        report[3] = 0x00

        let dataOffset = 4

        // Valid flags - same as USB
        report[dataOffset + 0] = 0xFF  // flag0: enable all
        report[dataOffset + 1] = 0x57  // flag1: 0x01|0x02|0x04|0x10|0x40

        // Mute button LED (byte 9 from data start)
        report[dataOffset + DualSenseHIDConstants.muteButtonLEDOffset] = settings.muteButtonLED.byteValue

        // LED brightness (byte 43 from data start)
        report[dataOffset + DualSenseHIDConstants.ledBrightnessOffset] = settings.lightBarBrightness.byteValue

        // Player LEDs (byte 44 from data start)
        report[dataOffset + DualSenseHIDConstants.playerLEDsOffset] = settings.playerLEDs.bitmask

        // Light bar color (bytes 45, 46, 47 from data start)
        report[dataOffset + DualSenseHIDConstants.lightbarRedOffset] = settings.lightBarColor.redByte
        report[dataOffset + DualSenseHIDConstants.lightbarGreenOffset] = settings.lightBarColor.greenByte
        report[dataOffset + DualSenseHIDConstants.lightbarBlueOffset] = settings.lightBarColor.blueByte

        // Calculate CRC32 for Bluetooth (last 4 bytes)
        let crcData = Data([0xA2] + report[1..<74])
        let crc = crc32(crcData)
        report[74] = UInt8(crc & 0xFF)
        report[75] = UInt8((crc >> 8) & 0xFF)
        report[76] = UInt8((crc >> 16) & 0xFF)
        report[77] = UInt8((crc >> 24) & 0xFF)

        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualSenseHIDConstants.bluetoothOutputReportID),
            report,
            report.count
        )

        if result != kIOReturnSuccess {
            print("Failed to send Bluetooth LED report: \(result)")
        }
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0)
            }
        }
        return ~crc
    }

    nonisolated private func handleHIDReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // Only process report 0x31 (Bluetooth input report) with sufficient length
        guard reportID == 0x31 && length >= 12 else { return }

        // Mic button is at byte 11, bit 2 in Bluetooth report
        // Report structure: [0]=reportID, ... [11]=buttons2 (PS/Touch/Mute)
        let buttons2 = report[11]
        let micPressed = (buttons2 & 0x04) != 0

        // Detect state change (thread-safe)
        storage.lock.lock()
        let changed = micPressed != storage.lastMicButtonState
        if changed {
            storage.lastMicButtonState = micPressed
        }
        storage.lock.unlock()

        if changed {
            controllerQueue.async { [weak self] in
                self?.handleButton(.micMute, pressed: micPressed)
            }
        }
    }

    // MARK: - Thread-Safe Update Helpers
    
    nonisolated private func updateLeftStick(x: Float, y: Float) {
        storage.lock.lock()
        storage.leftStick = CGPoint(x: CGFloat(x), y: CGFloat(y))
        storage.lock.unlock()
        
        Task { @MainActor in
            self.onLeftStickMoved?(CGPoint(x: CGFloat(x), y: CGFloat(y)))
        }
    }
    
    nonisolated private func updateRightStick(x: Float, y: Float) {
        storage.lock.lock()
        storage.rightStick = CGPoint(x: CGFloat(x), y: CGFloat(y))
        storage.lock.unlock()

        Task { @MainActor in
            self.onRightStickMoved?(CGPoint(x: CGFloat(x), y: CGFloat(y)))
        }
    }

    nonisolated private func updateTouchpad(x: Float, y: Float) {
        defer { logTouchpadDebugIfNeeded(source: "primary") }
        storage.lock.lock()

        let newPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let wasTouching = storage.isTouchpadTouching
        let wasTwoFinger = storage.isTouchpadTouching && storage.isTouchpadSecondaryTouching
        let gestureCallback = storage.onTouchpadGesture
        let now = CFAbsoluteTimeGetCurrent()
        let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
        if secondaryFresh {
            storage.touchpadMovementBlocked = true
        }

        // Detect if finger is on touchpad (non-zero position indicates touch)
        // GCControllerDirectionPad returns 0,0 when no finger is present
        let isTouching = abs(x) > 0.001 || abs(y) > 0.001

        if isTouching {
            if wasTouching {
                if storage.touchpadClickArmed {
                    let distance = Double(hypot(
                        newPosition.x - storage.touchpadClickStartPosition.x,
                        newPosition.y - storage.touchpadClickStartPosition.y
                    ))
                    if distance < Config.touchpadClickMovementThreshold {
                        storage.touchpadPosition = newPosition
                        storage.touchpadPreviousPosition = newPosition
                        storage.pendingTouchpadDelta = nil
                        storage.lock.unlock()
                        return
                    }

                    storage.touchpadClickArmed = false
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.pendingTouchpadDelta = nil
                    storage.lock.unlock()
                    return
                }

                if storage.touchpadMovementBlocked || secondaryFresh {
                    storage.pendingTouchpadDelta = nil
                    storage.touchpadPreviousPosition = newPosition
                    storage.touchpadPosition = newPosition
                    storage.lock.unlock()
                    return
                }

                // Increment frame counter
                storage.touchpadFramesSinceTouch += 1

                // Skip first 2 frames after touch to let position settle
                // This prevents spurious movement when finger first contacts touchpad
                if storage.touchpadFramesSinceTouch <= 2 {
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.lock.unlock()
                    return
                }

                // Touch settle: suppress movement for short taps/holds where finger is stationary
                // Only allow movement after settle time OR finger has moved significantly from start
                let timeSinceTouchStart = now - storage.touchpadTouchStartTime
                let distanceFromStart = Double(hypot(
                    newPosition.x - storage.touchpadTouchStartPosition.x,
                    newPosition.y - storage.touchpadTouchStartPosition.y
                ))
                let inSettlePeriod = timeSinceTouchStart < Config.touchpadTouchSettleInterval
                let belowMovementThreshold = distanceFromStart < Config.touchpadClickMovementThreshold

                if inSettlePeriod && belowMovementThreshold {
                    // Still settling - update position but don't generate movement
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.pendingTouchpadDelta = nil
                    storage.lock.unlock()
                    return
                }

                // Finger still touching - calculate delta
                let delta = CGPoint(
                    x: newPosition.x - storage.touchpadPosition.x,
                    y: newPosition.y - storage.touchpadPosition.y
                )

                // Detect sudden large jumps which indicate:
                // 1. Finger lift (touchpad sends edge position before resetting)
                // 2. Position wrap/reset during long drags
                // Ignore deltas larger than threshold (normal finger movement is much smaller)
                let jumpThreshold: CGFloat = 0.3
                let isJump = abs(delta.x) > jumpThreshold || abs(delta.y) > jumpThreshold

                if isJump {
                    // Treat as new touch - reset position, don't apply delta
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.pendingTouchpadDelta = nil
                    storage.lock.unlock()
                    return
                }

                storage.touchpadPreviousPosition = storage.touchpadPosition
                storage.touchpadPosition = newPosition

                // Apply the PREVIOUS pending delta (if any), then store current as pending
                // This 1-frame delay filters out artifacts right before finger lift
                let previousPending = storage.pendingTouchpadDelta
                let callback = storage.onTouchpadMoved

                // Store current delta as pending for next frame
                if abs(delta.x) > 0.001 || abs(delta.y) > 0.001 {
                    storage.pendingTouchpadDelta = delta
                } else {
                    storage.pendingTouchpadDelta = nil
                }

                let distance = hypot(
                    storage.touchpadPosition.x - storage.touchpadSecondaryPosition.x,
                    storage.touchpadPosition.y - storage.touchpadSecondaryPosition.y
                )
                let isTwoFinger = secondaryFresh && Double(distance) > Config.touchpadTwoFingerMinDistance
                var gesture: TouchpadGesture?
                if isTwoFinger {
                    let currentCenter = CGPoint(
                        x: (storage.touchpadPosition.x + storage.touchpadSecondaryPosition.x) * 0.5,
                        y: (storage.touchpadPosition.y + storage.touchpadSecondaryPosition.y) * 0.5
                    )
                    let previousCenter = CGPoint(
                        x: (storage.touchpadPreviousPosition.x + storage.touchpadSecondaryPreviousPosition.x) * 0.5,
                        y: (storage.touchpadPreviousPosition.y + storage.touchpadSecondaryPreviousPosition.y) * 0.5
                    )
                    let centerDelta = CGPoint(
                        x: currentCenter.x - previousCenter.x,
                        y: currentCenter.y - previousCenter.y
                    )
                    let currentDistance = distance
                    let previousDistance = hypot(
                        storage.touchpadPreviousPosition.x - storage.touchpadSecondaryPreviousPosition.x,
                        storage.touchpadPreviousPosition.y - storage.touchpadSecondaryPreviousPosition.y
                    )
                    gesture = TouchpadGesture(
                        centerDelta: centerDelta,
                        distanceDelta: Double(currentDistance - previousDistance),
                        isPrimaryTouching: storage.isTouchpadTouching,
                        isSecondaryTouching: storage.isTouchpadSecondaryTouching
                    )
                }

                let isSecondaryTouching = storage.isTouchpadSecondaryTouching
                storage.lock.unlock()

                if let gesture {
                    gestureCallback?(gesture)
                } else if let pending = previousPending, !isSecondaryTouching {
                    callback?(pending)
                }
            } else {
                // Finger just touched - initialize position, no delta yet
                storage.touchpadPosition = newPosition
                storage.touchpadPreviousPosition = newPosition
                storage.isTouchpadTouching = true
                storage.touchpadFramesSinceTouch = 0
                storage.pendingTouchpadDelta = nil
                storage.touchpadTouchStartTime = now
                storage.touchpadTouchStartPosition = newPosition
                if storage.touchpadClickArmed {
                    storage.touchpadClickStartPosition = newPosition
                }
                storage.lock.unlock()
            }
        } else {
            // Finger lifted - discard any pending delta (it was likely lift artifact)
            storage.isTouchpadTouching = false
            storage.touchpadPosition = .zero
            storage.touchpadPreviousPosition = .zero
            storage.touchpadFramesSinceTouch = 0
            storage.pendingTouchpadDelta = nil
            storage.touchpadClickArmed = false
            storage.touchpadMovementBlocked = false
            let isSecondaryTouching = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
            let isTwoFinger = storage.isTouchpadTouching && isSecondaryTouching
            storage.lock.unlock()

            if wasTwoFinger && !isTwoFinger {
                gestureCallback?(TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: false,
                    isSecondaryTouching: isSecondaryTouching
                ))
            }
        }
    }

    nonisolated private func updateTouchpadSecondary(x: Float, y: Float) {
        defer { logTouchpadDebugIfNeeded(source: "secondary") }
        storage.lock.lock()

        let newPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let wasTouching = storage.isTouchpadSecondaryTouching
        let wasTwoFinger = storage.isTouchpadTouching && storage.isTouchpadSecondaryTouching
        let gestureCallback = storage.onTouchpadGesture
        let now = CFAbsoluteTimeGetCurrent()

        // Detect if finger is on touchpad (non-zero position indicates touch)
        let isTouching = abs(x) > 0.001 || abs(y) > 0.001

        if isTouching {
            if wasTouching {
                storage.touchpadSecondaryFramesSinceTouch += 1
                storage.touchpadSecondaryLastUpdate = now
                storage.touchpadSecondaryLastTouchTime = now

                // Skip first 2 frames after touch to let position settle
                if storage.touchpadSecondaryFramesSinceTouch <= 2 {
                    storage.touchpadSecondaryPosition = newPosition
                    storage.touchpadSecondaryPreviousPosition = newPosition
                    storage.lock.unlock()
                    return
                }

                let delta = CGPoint(
                    x: newPosition.x - storage.touchpadSecondaryPosition.x,
                    y: newPosition.y - storage.touchpadSecondaryPosition.y
                )

                let jumpThreshold: CGFloat = 0.3
                let isJump = abs(delta.x) > jumpThreshold || abs(delta.y) > jumpThreshold
                if isJump {
                    storage.touchpadSecondaryPosition = newPosition
                    storage.touchpadSecondaryPreviousPosition = newPosition
                    storage.lock.unlock()
                    return
                }

                storage.touchpadSecondaryPreviousPosition = storage.touchpadSecondaryPosition
                storage.touchpadSecondaryPosition = newPosition
            } else {
                storage.touchpadSecondaryPosition = newPosition
                storage.touchpadSecondaryPreviousPosition = newPosition
                storage.isTouchpadSecondaryTouching = true
                storage.touchpadSecondaryFramesSinceTouch = 0
                storage.touchpadSecondaryLastUpdate = now
                storage.touchpadSecondaryLastTouchTime = now
                storage.touchpadMovementBlocked = true
                let isPrimaryTouching = storage.isTouchpadTouching
                let gestureCallback = storage.onTouchpadGesture
                storage.lock.unlock()

                if isPrimaryTouching {
                    gestureCallback?(TouchpadGesture(
                        centerDelta: .zero,
                        distanceDelta: 0,
                        isPrimaryTouching: true,
                        isSecondaryTouching: true
                    ))
                }
                return
            }

            let distance = hypot(
                storage.touchpadPosition.x - storage.touchpadSecondaryPosition.x,
                storage.touchpadPosition.y - storage.touchpadSecondaryPosition.y
            )
            let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
            let isTwoFinger = storage.isTouchpadTouching &&
                secondaryFresh &&
                Double(distance) > Config.touchpadTwoFingerMinDistance
            if isTwoFinger {
                let currentCenter = CGPoint(
                    x: (storage.touchpadPosition.x + storage.touchpadSecondaryPosition.x) * 0.5,
                    y: (storage.touchpadPosition.y + storage.touchpadSecondaryPosition.y) * 0.5
                )
                let previousCenter = CGPoint(
                    x: (storage.touchpadPreviousPosition.x + storage.touchpadSecondaryPreviousPosition.x) * 0.5,
                    y: (storage.touchpadPreviousPosition.y + storage.touchpadSecondaryPreviousPosition.y) * 0.5
                )
                let centerDelta = CGPoint(
                    x: currentCenter.x - previousCenter.x,
                    y: currentCenter.y - previousCenter.y
                )
                let currentDistance = distance
                let previousDistance = hypot(
                    storage.touchpadPreviousPosition.x - storage.touchpadSecondaryPreviousPosition.x,
                    storage.touchpadPreviousPosition.y - storage.touchpadSecondaryPreviousPosition.y
                )
                let gesture = TouchpadGesture(
                    centerDelta: centerDelta,
                    distanceDelta: Double(currentDistance - previousDistance),
                    isPrimaryTouching: storage.isTouchpadTouching,
                    isSecondaryTouching: storage.isTouchpadSecondaryTouching
                )
                storage.lock.unlock()
                gestureCallback?(gesture)
            } else {
                storage.lock.unlock()
            }
        } else {
            storage.isTouchpadSecondaryTouching = false
            storage.touchpadSecondaryPosition = .zero
            storage.touchpadSecondaryPreviousPosition = .zero
            storage.touchpadSecondaryFramesSinceTouch = 0
            storage.touchpadSecondaryLastUpdate = now
            storage.touchpadMovementBlocked = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
            let isPrimaryTouching = storage.isTouchpadTouching
            let isTwoFinger = isPrimaryTouching && storage.isTouchpadSecondaryTouching
            storage.lock.unlock()

            if wasTwoFinger && !isTwoFinger {
                gestureCallback?(TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: isPrimaryTouching,
                    isSecondaryTouching: false
                ))
            } else if isPrimaryTouching {
                gestureCallback?(TouchpadGesture(
                    centerDelta: .zero,
                    distanceDelta: 0,
                    isPrimaryTouching: true,
                    isSecondaryTouching: false
                ))
            }
        }
    }

    nonisolated private func logTouchpadDebugIfNeeded(source: String) {
        let envEnabled = ProcessInfo.processInfo.environment[Config.touchpadDebugEnvKey] == "1"
        let defaultsEnabled = UserDefaults.standard.bool(forKey: Config.touchpadDebugLoggingKey)
        guard envEnabled || defaultsEnabled else { return }

        let now = CFAbsoluteTimeGetCurrent()
        storage.lock.lock()
        if now - storage.touchpadDebugLastLogTime < Config.touchpadDebugLogInterval {
            storage.lock.unlock()
            return
        }
        storage.touchpadDebugLastLogTime = now

        let primary = storage.touchpadPosition
        let secondary = storage.touchpadSecondaryPosition
        let primaryTouching = storage.isTouchpadTouching
        let secondaryTouching = storage.isTouchpadSecondaryTouching
        let blocked = storage.touchpadMovementBlocked
        let distance = hypot(primary.x - secondary.x, primary.y - secondary.y)
        let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
        storage.lock.unlock()

        print(String(
            format: "TP[%@] p=(%.3f,%.3f) s=(%.3f,%.3f) touch=%d/%d blocked=%d dist=%.3f fresh=%d",
            source,
            primary.x, primary.y,
            secondary.x, secondary.y,
            primaryTouching ? 1 : 0,
            secondaryTouching ? 1 : 0,
            blocked ? 1 : 0,
            distance,
            secondaryFresh ? 1 : 0
        ))
    }

    nonisolated private func armTouchpadClick(pressed: Bool) {
        storage.lock.lock()
        if pressed {
            storage.touchpadClickArmed = true
            storage.touchpadClickStartPosition = storage.touchpadPosition
            storage.pendingTouchpadDelta = nil
            storage.touchpadFramesSinceTouch = 0
        } else {
            storage.touchpadClickArmed = false
        }
        storage.lock.unlock()
    }

    nonisolated private func updateLeftTrigger(_ value: Float, pressed: Bool) {
        storage.lock.lock()
        storage.leftTrigger = value
        storage.lock.unlock()
        
        controllerQueue.async {
            self.handleButton(.leftTrigger, pressed: pressed)
        }
    }
    
    nonisolated private func updateRightTrigger(_ value: Float, pressed: Bool) {
        storage.lock.lock()
        storage.rightTrigger = value
        storage.lock.unlock()
        
        controllerQueue.async {
            self.handleButton(.rightTrigger, pressed: pressed)
        }
    }

    nonisolated private func handleButton(_ button: ControllerButton, pressed: Bool) {
        if pressed {
            buttonPressed(button)
        } else {
            buttonReleased(button)
        }
    }

    nonisolated internal func buttonPressed(_ button: ControllerButton) {
        storage.lock.lock()
        
        // Fast Double Tap Check
        if storage.capturedButtonsInWindow.contains(button) {
            storage.chordWorkItem?.cancel()
            storage.lock.unlock()
            processChordOrSinglePress()
            storage.lock.lock()
        }

        guard !storage.activeButtons.contains(button) else {
            storage.lock.unlock()
            return
        }

        storage.activeButtons.insert(button)
        storage.buttonPressTimestamps[button] = Date()
        storage.pendingButtons.insert(button)
        storage.capturedButtonsInWindow.insert(button)
        
        let uiButtons = storage.activeButtons
        
        // Chord Detection
        storage.chordWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.processChordOrSinglePress()
        }
        storage.chordWorkItem = workItem
        let window = storage.chordWindow
        storage.lock.unlock()
        
        Task { @MainActor in
            self.activeButtons = uiButtons
        }
        
        controllerQueue.asyncAfter(deadline: .now() + window, execute: workItem)
    }

    nonisolated internal func buttonReleased(_ button: ControllerButton) {
        storage.lock.lock()
        guard storage.activeButtons.contains(button) else {
            storage.lock.unlock()
            return
        }

        storage.activeButtons.remove(button)
        let pressTime = storage.buttonPressTimestamps.removeValue(forKey: button)
        let uiButtons = storage.activeButtons
        storage.lock.unlock()
        
        Task { @MainActor in
            self.activeButtons = uiButtons
        }
        
        let holdDuration: TimeInterval
        if let time = pressTime {
            holdDuration = Date().timeIntervalSince(time)
        } else {
            holdDuration = 0
        }

        storage.lock.lock()
        if storage.pendingButtons.contains(button) {
            storage.pendingReleases[button] = holdDuration
            storage.lock.unlock()
        } else {
            let callback = storage.onButtonReleased
            storage.lock.unlock()
            callback?(button, holdDuration)
        }
    }

    nonisolated private func processChordOrSinglePress() {
        storage.lock.lock()
        let captured = storage.capturedButtonsInWindow
        
        // Clear state
        storage.capturedButtonsInWindow.removeAll()
        storage.pendingButtons.removeAll()
        
        // Copy releases to process
        let releases = storage.pendingReleases
        storage.pendingReleases.removeAll()
        
        let chordCallback = storage.onChordDetected
        let pressCallback = storage.onButtonPressed
        let releaseCallback = storage.onButtonReleased
        
        storage.lock.unlock()

        if captured.count >= 2 {
            chordCallback?(captured)
        } else if let button = captured.first {
            pressCallback?(button)
        }
        
        for button in captured {
            if let duration = releases[button] {
                releaseCallback?(button, duration)
            }
        }
    }

    // MARK: - Haptic Feedback

    private func setupHaptics(for controller: GCController) {
        guard let haptics = controller.haptics else {
            return
        }

        // Try multiple localities - Xbox controllers may respond to different ones
        let localities: [GCHapticsLocality] = [.default, .handles, .leftHandle, .rightHandle, .leftTrigger, .rightTrigger]

        for locality in localities {
            if let engine = haptics.createEngine(withLocality: locality) {
                engine.resetHandler = { [weak engine] in
                    // Restart engine if it stops
                    try? engine?.start()
                }
                do {
                    try engine.start()
                    hapticEngines.append(engine)
                } catch {
                    // Engine startup failed, continue to next locality
                }
            }
        }
    }

    private func stopHaptics() {
        for engine in hapticEngines {
            engine.stop()
        }
        hapticEngines.removeAll()
    }

    /// Plays a haptic pulse on the controller
    /// - Parameters:
    ///   - intensity: Haptic intensity from 0.0 to 1.0
    ///   - duration: Duration in seconds
    nonisolated func playHaptic(intensity: Float = 0.5, sharpness: Float = 0.5, duration: TimeInterval = 0.1) {
        hapticQueue.async { [weak self] in
            guard let engines = self?.hapticEngines, !engines.isEmpty else { return }

            // Use continuous haptic for more noticeable feedback on game controllers
            do {
                let events = [
                    CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                        ],
                        relativeTime: 0,
                        duration: duration
                    )
                ]
                let pattern = try CHHapticPattern(events: events, parameters: [])

                // Play on all available engines for maximum effect
                for engine in engines {
                    do {
                        let player = try engine.makePlayer(with: pattern)
                        try player.start(atTime: CHHapticTimeImmediate)
                    } catch {
                        // Try to restart engine and retry once
                        try? engine.start()
                        if let player = try? engine.makePlayer(with: pattern) {
                            try? player.start(atTime: CHHapticTimeImmediate)
                        }
                    }
                }
            } catch {
                // Haptic pattern error, continue silently
            }
        }
    }
}
