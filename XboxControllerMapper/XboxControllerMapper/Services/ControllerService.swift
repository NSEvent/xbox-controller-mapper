import Foundation
import GameController
import Combine
import CoreHaptics
import IOKit
import IOKit.hid
import SwiftUI
import CoreAudio
import AudioToolbox
import AVFoundation

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
    static let powerSaveControlOffset = 9
    static let validFlag2Offset = 38
    static let lightbarSetupOffset = 41
    static let ledBrightnessOffset = 42
    static let playerLEDsOffset = 43
    static let lightbarRedOffset = 44
    static let lightbarGreenOffset = 45
    static let lightbarBlueOffset = 46

    // Valid flag bits
    static let validFlag1MuteLED: UInt8 = 0x01
    static let validFlag1PowerSaveControl: UInt8 = 0x02
    static let validFlag1Lightbar: UInt8 = 0x04
    static let validFlag1PlayerLEDs: UInt8 = 0x10
    static let validFlag2LightbarSetup: UInt8 = 0x02
    static let validFlag2LEDBrightness: UInt8 = 0x01

    // Power save control bits
    static let powerSaveControlMicMute: UInt8 = 0x10

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
    var touchpadGestureHasCenter: Bool = false
    var touchpadGesturePreviousCenter: CGPoint = .zero
    var touchpadGesturePreviousDistance: Double = 0
    var touchpadSecondaryLastUpdate: TimeInterval = 0
    var touchpadSecondaryLastTouchTime: TimeInterval = 0
    var isDualSense: Bool = false
    var isDualSenseEdge: Bool = false
    var isBluetoothConnection: Bool = false
    var currentLEDSettings: DualSenseLEDSettings?
    var pendingTouchpadDelta: CGPoint? = nil  // Delayed by 1 frame to filter lift artifacts
    var touchpadFramesSinceTouch: Int = 0  // Skip first frames after touch to let position settle
    var touchpadSecondaryFramesSinceTouch: Int = 0
    var touchpadClickArmed: Bool = false
    var touchpadClickStartPosition: CGPoint = .zero
    var touchpadClickFiredDuringTouch: Bool = false  // Suppress tap after physical click
    var touchpadMovementBlocked: Bool = false
    var touchpadTouchStartTime: TimeInterval = 0  // Time when finger first touched
    var touchpadTouchStartPosition: CGPoint = .zero  // Position when finger first touched
    var touchpadMaxDistanceFromStart: Double = 0  // Max distance traveled during touch (for tap detection)
    var touchpadLastTapTime: TimeInterval = 0  // Time of last detected tap (for double-tap cooldown)
    var touchpadDebugLastLogTime: TimeInterval = 0
    var touchpadIdleSentinel: CGPoint? = nil
    var touchpadSecondaryIdleSentinel: CGPoint? = nil
    var touchpadHasSeenTouch: Bool = false
    var touchpadSecondaryHasSeenTouch: Bool = false

    // Two-finger tap detection
    var touchpadSecondaryTouchStartTime: TimeInterval = 0
    var touchpadSecondaryTouchStartPosition: CGPoint = .zero
    var touchpadSecondaryMaxDistanceFromStart: Double = 0
    var touchpadTwoFingerClickArmed: Bool = false  // Track button press with two fingers
    var touchpadWasTwoFingerDuringTouch: Bool = false  // Track if two fingers touched during this primary touch
    var touchpadTwoFingerGestureDistance: Double = 0  // Cumulative center movement during two-finger gesture
    var touchpadTwoFingerPinchDistance: Double = 0  // Cumulative pinch (distance change) during two-finger gesture

    // Button State
    var activeButtons: Set<ControllerButton> = []
    var buttonPressTimestamps: [ControllerButton: Date] = [:]
    var lastMicButtonState: Bool = false
    var lastPSButtonState: Bool = false

    // DualSense Edge button state (paddles and function buttons)
    var lastLeftPaddleState: Bool = false
    var lastRightPaddleState: Bool = false
    var lastLeftFunctionState: Bool = false
    var lastRightFunctionState: Bool = false

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
    var onTouchpadTap: (() -> Void)?  // Single tap (touch + release without moving)
    var onTouchpadTwoFingerTap: (() -> Void)?  // Two-finger tap or click (right-click)
    var onTouchpadLongTap: (() -> Void)?  // Long tap (touch held without moving)
    var onTouchpadTwoFingerLongTap: (() -> Void)?  // Two-finger long tap
    var touchpadLongTapTimer: DispatchWorkItem?  // Timer for long tap detection
    var touchpadLongTapFired: Bool = false  // Whether long tap already triggered for this touch
}

/// Service for managing game controller connection and input
@MainActor
class ControllerService: ObservableObject {
    @Published var isConnected = false
    @Published var connectedController: GCController?
    @Published var controllerName: String = ""

    /// Currently pressed buttons (UI use only, updated asynchronously)
    @Published var activeButtons: Set<ControllerButton> = []

    /// Party mode state
    @Published var partyModeEnabled = false

    /// Keep-alive mode - sends periodic signal to prevent controller sleep
    @Published var keepAliveEnabled = false

    /// Whether the current connection is Bluetooth (for UI display)
    @Published var isBluetoothConnection = false

    /// Microphone state
    @Published var isMicMuted = false
    @Published var micAudioLevel: Float = 0.0
    private var micDeviceID: AudioDeviceID?
    private var micLevelTimer: Timer?
    private var audioEngine: AVAudioEngine?

    private var partyModeTimer: Timer?
    private var partyHue: Double = 0.0
    private var partyLEDIndex: Int = 0
    private var partyLEDDirection: Int = 1

    private var keepAliveTimer: Timer?
    private let keepAliveInterval: TimeInterval = 30.0  // Send signal every 30 seconds

    private let partyLEDPatterns: [PlayerLEDs] = [
        PlayerLEDs(led1: false, led2: false, led3: true, led4: false, led5: false),
        PlayerLEDs(led1: false, led2: true, led3: false, led4: true, led5: false),
        PlayerLEDs(led1: true, led2: false, led3: false, led4: false, led5: true),
        PlayerLEDs(led1: true, led2: true, led3: false, led4: true, led5: true),
        PlayerLEDs(led1: true, led2: true, led3: true, led4: true, led5: true),
    ]

    private let controllerQueue = DispatchQueue(label: "com.xboxmapper.controller", qos: .userInteractive)
    private let storage = ControllerStorage()

    // HID monitoring for DualSense mic button (not exposed by GameController framework)
    private var hidManager: IOHIDManager?
    private var hidReportBuffer: UnsafeMutablePointer<UInt8>?
    private var hidDevice: IOHIDDevice?
    private var bluetoothOutputSeq: UInt8 = 0  // Sequence number for Bluetooth output reports (0-15)

    // Generic HID controller fallback (for controllers not recognized by GameController framework)
    private var genericHIDManager: IOHIDManager?
    private var genericHIDController: GenericHIDController?
    private var genericHIDFallbackTimer: DispatchWorkItem?
    @Published var isGenericController = false

    private enum TouchpadIdleSentinelConfig {
        static let activationThreshold: CGFloat = 0.02
    }
    
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

    nonisolated var threadSafeIsDualSenseEdge: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isDualSenseEdge
    }

    nonisolated var threadSafeIsBluetoothConnection: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isBluetoothConnection
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
    var onTouchpadTap: (() -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onTouchpadTap }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onTouchpadTap = newValue }
    }
    var onTouchpadTwoFingerTap: (() -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onTouchpadTwoFingerTap }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onTouchpadTwoFingerTap = newValue }
    }
    var onTouchpadLongTap: (() -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onTouchpadLongTap }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onTouchpadLongTap = newValue }
    }
    var onTouchpadTwoFingerLongTap: (() -> Void)? {
        get { storage.lock.lock(); defer { storage.lock.unlock() }; return storage.onTouchpadTwoFingerLongTap }
        set { storage.lock.lock(); defer { storage.lock.unlock() }; storage.onTouchpadTwoFingerLongTap = newValue }
    }

    private var cancellables = Set<AnyCancellable>()
    
    // Low-level monitor for Xbox Guide button
    private let guideMonitor = XboxGuideMonitor()
    
    // Low-level monitor for Battery (Bluetooth Workaround for macOS/Xbox issue)
    private let batteryMonitor = BluetoothBatteryMonitor()

    // Haptic engines for controller feedback (try multiple localities)
    private var hapticEngines: [CHHapticEngine] = []
    private let hapticQueue = DispatchQueue(label: "com.xboxmapper.haptic", qos: .userInitiated)
    private struct ActiveHapticPlayer {
        let player: CHHapticPatternPlayer
        let endTime: TimeInterval
    }
    private var activeHapticPlayers: [ActiveHapticPlayer] = []

    init() {
        GCController.shouldMonitorBackgroundEvents = true

        // Load last controller type (so UI shows correct button labels when no controller is connected)
        storage.isDualSense = UserDefaults.standard.bool(forKey: Config.lastControllerWasDualSenseKey)

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

        setupGenericHIDMonitoring()
    }

    func cleanup() {
        stopDiscovery()
        batteryMonitor.stopMonitoring()
        cleanupGenericHIDMonitoring()
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
        // Cancel generic HID fallback if GameController framework claimed this device
        genericHIDFallbackTimer?.cancel()
        genericHIDFallbackTimer = nil
        if genericHIDController != nil {
            genericHIDController?.stop()
            genericHIDController = nil
            isGenericController = false
        }

        connectedController = controller
        isConnected = true
        controllerName = controller.vendorName ?? "Game Controller"

        storage.lock.lock()
        resetTouchpadStateLocked()
        storage.lock.unlock()

        setupInputHandlers(for: controller)
        setupHaptics(for: controller)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.playHaptic(intensity: 0.7, sharpness: 0.6, duration: 0.12)
        }
        updateBatteryInfo()
        startDisplayUpdateTimer()
    }

    private func controllerDisconnected() {
        connectedController = nil
        isConnected = false
        isGenericController = false
        controllerName = ""
        activeButtons.removeAll()
        leftStick = .zero
        rightStick = .zero
        batteryLevel = -1
        batteryState = .unknown
        batteryMonitor.resetBatteryLevel()  // Clear stale battery reading
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
        // Reset touchpad state (but keep isDualSense to remember last controller type)
        resetTouchpadStateLocked()
        storage.lastMicButtonState = false
        storage.lock.unlock()
    }

    private func resetTouchpadStateLocked() {
        storage.isTouchpadTouching = false
        storage.isTouchpadSecondaryTouching = false
        storage.touchpadPosition = .zero
        storage.touchpadPreviousPosition = .zero
        storage.touchpadSecondaryPosition = .zero
        storage.touchpadSecondaryPreviousPosition = .zero
        storage.touchpadGestureHasCenter = false
        storage.touchpadGesturePreviousCenter = .zero
        storage.touchpadGesturePreviousDistance = 0
        storage.touchpadSecondaryLastUpdate = 0
        storage.touchpadSecondaryLastTouchTime = 0
        storage.pendingTouchpadDelta = nil
        storage.touchpadFramesSinceTouch = 0
        storage.touchpadSecondaryFramesSinceTouch = 0
        storage.touchpadClickArmed = false
        storage.touchpadClickStartPosition = .zero
        storage.touchpadClickFiredDuringTouch = false
        storage.touchpadMovementBlocked = false
        storage.touchpadTouchStartTime = 0
        storage.touchpadTouchStartPosition = .zero
        storage.touchpadIdleSentinel = nil
        storage.touchpadSecondaryIdleSentinel = nil
        storage.touchpadHasSeenTouch = false
        storage.touchpadSecondaryHasSeenTouch = false
    }

    // MARK: - Generic HID Controller Fallback

    private func setupGenericHIDMonitoring() {
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

    private func cleanupGenericHIDMonitoring() {
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

    fileprivate func genericDeviceAppeared(_ device: IOHIDDevice) {
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

    private func attemptGenericFallback(device: IOHIDDevice, vendorID: Int, productID: Int,
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

    fileprivate func genericDeviceRemoved(_ device: IOHIDDevice) {
        // Only handle if this is our active generic controller's device
        guard let controller = genericHIDController, controller.device == device else { return }
        controller.stop()
        genericHIDController = nil
        controllerDisconnected()
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
        // Use appropriate battery source based on controller type:
        // - DualSense: GCController.battery works reliably
        // - Xbox: Use BluetoothBatteryMonitor workaround (GCController often returns -1/0 on macOS)
        let isDualSense = threadSafeIsDualSense

        if !isDualSense, let ioLevel = batteryMonitor.batteryLevel {
            // Xbox controller: prefer Bluetooth monitor (macOS workaround)
            batteryLevel = Float(ioLevel) / 100.0
            batteryState = batteryMonitor.isCharging ? .charging : .discharging
        } else if let battery = connectedController?.battery {
            // DualSense or Xbox fallback: use GCController battery
            batteryLevel = battery.batteryLevel
            batteryState = battery.batteryState
        }

        if isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.batteryUpdateInterval) { [weak self] in
                self?.updateBatteryInfo()
            }
        }
    }

    /// Helper to bind a GCControllerButtonInput to a ControllerButton
    private func bindButton(_ element: GCControllerButtonInput?, to button: ControllerButton) {
        element?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.controllerQueue.async { self?.handleButton(button, pressed: pressed) }
        }
    }

    private func setupInputHandlers(for controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }

        // Face buttons
        bindButton(gamepad.buttonA, to: .a)
        bindButton(gamepad.buttonB, to: .b)
        bindButton(gamepad.buttonX, to: .x)
        bindButton(gamepad.buttonY, to: .y)

        // Bumpers
        bindButton(gamepad.leftShoulder, to: .leftBumper)
        bindButton(gamepad.rightShoulder, to: .rightBumper)

        // Triggers
        gamepad.leftTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            self?.updateLeftTrigger(value, pressed: pressed)
        }
        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            self?.updateRightTrigger(value, pressed: pressed)
        }

        // D-pad
        bindButton(gamepad.dpad.up, to: .dpadUp)
        bindButton(gamepad.dpad.down, to: .dpadDown)
        bindButton(gamepad.dpad.left, to: .dpadLeft)
        bindButton(gamepad.dpad.right, to: .dpadRight)

        // Special buttons
        bindButton(gamepad.buttonMenu, to: .menu)
        bindButton(gamepad.buttonOptions, to: .view)
        bindButton((gamepad as? GCExtendedGamepad)?.buttonHome, to: .xbox)

        if let xboxGamepad = gamepad as? GCXboxGamepad {
            storage.lock.lock()
            storage.isDualSense = false
            storage.lock.unlock()
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)

            // Trigger battery monitor refresh for Xbox controller
            batteryMonitor.refreshBatteryLevel()

            bindButton(xboxGamepad.buttonShare, to: .share)
        }

        bindButton(gamepad.leftThumbstickButton, to: .leftThumbstick)
        bindButton(gamepad.rightThumbstickButton, to: .rightThumbstick)

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
            UserDefaults.standard.set(true, forKey: Config.lastControllerWasDualSenseKey)

            // Avoid system gesture delays on touchpad input
            dualSenseGamepad.touchpadPrimary.preferredSystemGestureState = .alwaysReceive
            dualSenseGamepad.touchpadSecondary.preferredSystemGestureState = .alwaysReceive
            dualSenseGamepad.touchpadButton.preferredSystemGestureState = .alwaysReceive

            // Touchpad button (click)
            // Two-finger + click triggers touchpadTwoFingerButton, single finger triggers touchpadButton
            dualSenseGamepad.touchpadButton.pressedChangedHandler = { [weak self] _, _, pressed in
                guard let self = self else { return }
                let isTwoFingerClick = self.armTouchpadClick(pressed: pressed)

                if pressed {
                    // On button press: check if this will be a two-finger click
                    self.storage.lock.lock()
                    let willBeTwoFingerClick = self.storage.touchpadTwoFingerClickArmed
                    self.storage.lock.unlock()

                    if willBeTwoFingerClick {
                        // Two-finger button press
                        self.controllerQueue.async { self.handleButton(.touchpadTwoFingerButton, pressed: true) }
                    } else {
                        // Normal single-finger button press
                        self.controllerQueue.async { self.handleButton(.touchpadButton, pressed: true) }
                    }
                } else {
                    // On button release
                    if isTwoFingerClick {
                        // Two-finger button release
                        self.controllerQueue.async { self.handleButton(.touchpadTwoFingerButton, pressed: false) }
                    } else {
                        // Normal single-finger button release
                        self.controllerQueue.async { self.handleButton(.touchpadButton, pressed: false) }
                    }
                }
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

        // Match DualSense and DualSense Edge controllers
        let dualSenseDict: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x054C,  // Sony
            kIOHIDProductIDKey as String: 0x0CE6, // DualSense
        ]
        let dualSenseEdgeDict: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x054C,  // Sony
            kIOHIDProductIDKey as String: 0x0DF2, // DualSense Edge
        ]
        let matchingDicts = [dualSenseDict, dualSenseEdgeDict] as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDicts)

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
        detectDualSenseEdge(device: device)
        guard let buffer = hidReportBuffer else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 100, { context, result, sender, type, reportID, report, reportLength in
            guard let context = context else { return }
            let service = Unmanaged<ControllerService>.fromOpaque(context).takeUnretainedValue()
            service.handleHIDReport(reportID: reportID, report: report, length: Int(reportLength))
        }, context)

        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        // Enable microphone when connected via USB
        storage.lock.lock()
        let isBluetooth = storage.isBluetoothConnection
        storage.lock.unlock()
        if !isBluetooth {
            enableMicrophone(device: device)
        }
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
            let isBluetooth = (transport.lowercased() == "bluetooth")
            #if DEBUG
            print("[LED] Detected connection type: \(transport) (isBluetooth=\(isBluetooth))")
            #endif
            storage.lock.lock()
            storage.isBluetoothConnection = isBluetooth
            storage.lock.unlock()
            // Update published property for UI
            isBluetoothConnection = isBluetooth
        } else {
            #if DEBUG
            print("[LED] Could not detect connection type, defaulting to USB")
            #endif
            isBluetoothConnection = false
        }
    }

    /// Detects if the connected device is a DualSense Edge (Pro) controller
    private func detectDualSenseEdge(device: IOHIDDevice) {
        if let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int {
            let isEdge = (productID == 0x0DF2)
            #if DEBUG
            print("[HID] Detected product ID: 0x\(String(productID, radix: 16)) (isEdge=\(isEdge))")
            #endif
            storage.lock.lock()
            storage.isDualSenseEdge = isEdge
            storage.lock.unlock()
        }
    }

    /// Enables the microphone on the DualSense controller using CoreAudio
    private func enableMicrophone(device: IOHIDDevice) {
        #if DEBUG
        print("[Mic] enableMicrophone called, searching for DualSense audio device...")
        #endif
        // Use CoreAudio to find and unmute the DualSense microphone
        unmuteDualSenseMicrophone()
    }

    /// Finds the DualSense audio input device and unmutes it via CoreAudio
    private func unmuteDualSenseMicrophone() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            #if DEBUG
            print("[Mic] Failed to get audio devices size: \(status)")
            #endif
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var audioDevices = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &audioDevices
        )

        guard status == noErr else {
            #if DEBUG
            print("[Mic] Failed to get audio devices: \(status)")
            #endif
            return
        }

        // Find and unmute ALL DualSense microphone devices
        // (There may be multiple audio devices for the same controller)
        var foundAny = false
        for deviceID in audioDevices {
            guard let deviceName = getAudioDeviceName(deviceID) else { continue }

            // Check if this is a DualSense device
            if deviceName.lowercased().contains("dualsense") ||
               deviceName.lowercased().contains("wireless controller") {

                // Check if it has input channels (is a microphone)
                if hasInputChannels(deviceID) {
                    #if DEBUG
                    print("[Mic] Found DualSense microphone: \(deviceName) (ID: \(deviceID))")
                    #endif
                    unmuteMicrophone(deviceID: deviceID)
                    foundAny = true
                }
            }
        }

        #if DEBUG
        if !foundAny {
            print("[Mic] DualSense microphone not found in audio devices")
        } else {
            print("[Mic] micDeviceID is now: \(String(describing: micDeviceID))")
        }
        #endif
    }

    private func getAudioDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        guard status == noErr, let deviceName = name else { return nil }
        return deviceName as String
    }

    private func hasInputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        let getStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
        guard getStatus == noErr else { return false }

        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0
    }

    private func unmuteMicrophone(deviceID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        // Check if mute property exists
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else {
            #if DEBUG
            print("[Mic] Device \(deviceID) does not have mute property, trying channel 1")
            #endif
            // Try with channel 1
            unmuteMicrophoneChannel(deviceID: deviceID, channel: 1)
            return
        }

        // Store this device as the controllable mic device
        micDeviceID = deviceID

        // Get current mute state
        var currentMuted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        var status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &currentMuted)
        #if DEBUG
        if status == noErr {
            print("[Mic] Current mute state for device \(deviceID): \(currentMuted == 1 ? "muted" : "unmuted")")
        }
        #endif

        // Set mute to false (0)
        var muteValue: UInt32 = 0
        status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &muteValue)

        if status == noErr {
            #if DEBUG
            print("[Mic] Successfully unmuted DualSense microphone (device \(deviceID))")
            #endif
            isMicMuted = false
        } else {
            #if DEBUG
            print("[Mic] Failed to unmute microphone: \(status)")
            #endif
            // Try channel-specific unmute
            unmuteMicrophoneChannel(deviceID: deviceID, channel: 1)
        }
    }

    private func unmuteMicrophoneChannel(deviceID: AudioDeviceID, channel: UInt32) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: channel
        )

        guard AudioObjectHasProperty(deviceID, &propertyAddress) else {
            #if DEBUG
            print("[Mic] Channel \(channel) does not have mute property")
            #endif
            return
        }

        var muteValue: UInt32 = 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &muteValue)

        #if DEBUG
        if status == noErr {
            print("[Mic] Successfully unmuted channel \(channel)")
        } else {
            print("[Mic] Failed to unmute channel \(channel): \(status)")
        }
        #endif
    }

    private func hasMuteProperty(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(deviceID, &propertyAddress)
    }

    // MARK: - Public Microphone Control

    /// Sets the mute state of the DualSense microphone
    func setMicMuted(_ muted: Bool) {
        guard let deviceID = micDeviceID else {
            #if DEBUG
            print("[Mic] No DualSense microphone device available")
            #endif
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var muteValue: UInt32 = muted ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &muteValue)

        if status == noErr {
            isMicMuted = muted
            #if DEBUG
            print("[Mic] Microphone \(muted ? "muted" : "unmuted")")
            #endif
        } else {
            #if DEBUG
            print("[Mic] Failed to set mute state: \(status)")
            #endif
        }
    }

    /// Starts monitoring the microphone audio level using AVAudioEngine
    func startMicLevelMonitoring() {
        stopMicLevelMonitoring()

        guard let deviceID = micDeviceID else {
            #if DEBUG
            print("[Mic] No DualSense microphone device for level monitoring")
            #endif
            return
        }

        // Request microphone permission first
        requestMicrophonePermission { [weak self] granted in
            guard granted else {
                #if DEBUG
                print("[Mic] Microphone permission denied")
                #endif
                return
            }

            guard let self = self else { return }

            Task { @MainActor in
                self.startAudioEngine()
            }
        }
    }

    /// Requests microphone permission from the user
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            #if DEBUG
            print("[Mic] Microphone permission already granted")
            #endif
            completion(true)
        case .notDetermined:
            #if DEBUG
            print("[Mic] Requesting microphone permission...")
            #endif
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                #if DEBUG
                print("[Mic] Microphone permission \(granted ? "granted" : "denied")")
                #endif
                completion(granted)
            }
        case .denied, .restricted:
            #if DEBUG
            print("[Mic] Microphone permission denied or restricted")
            #endif
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    /// Starts the audio engine for level monitoring (called after permission granted)
    private func startAudioEngine() {
        // Set DualSense as the input device BEFORE creating the engine
        setDualSenseAsInputDevice()

        // Small delay to let the system recognize the device change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }

            let engine = AVAudioEngine()

            // Force the engine to use the new default device
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            #if DEBUG
            print("[Mic] Audio format: \(format)")
            #endif

            // Install tap on input node to monitor audio levels
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self = self else { return }

                let channelData = buffer.floatChannelData?[0]
                let frameLength = Int(buffer.frameLength)

                guard let data = channelData, frameLength > 0 else { return }

                // Calculate RMS (root mean square) for audio level
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += data[i] * data[i]
                }
                let rms = sqrt(sum / Float(frameLength))

                // Convert to a 0-1 scale (with some amplification for visibility)
                let level = min(1.0, rms * 8.0)

                Task { @MainActor in
                    self.micAudioLevel = level
                }
            }

            do {
                try engine.start()
                self.audioEngine = engine
                #if DEBUG
                print("[Mic] Audio level monitoring started successfully")
                #endif
            } catch {
                #if DEBUG
                print("[Mic] Failed to start audio engine: \(error)")
                #endif
            }
        }
    }

    /// Stops monitoring the microphone audio level
    func stopMicLevelMonitoring() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
            #if DEBUG
            print("[Mic] Audio level monitoring stopped")
            #endif
        }
        micLevelTimer?.invalidate()
        micLevelTimer = nil
        micAudioLevel = 0
    }

    /// Gets the current default input device
    private func getCurrentDefaultInputDevice() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        return status == noErr ? deviceID : nil
    }

    /// Sets the DualSense microphone as the system input device for monitoring
    private func setDualSenseAsInputDevice() {
        guard let deviceID = micDeviceID else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDCopy = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDCopy
        )

        #if DEBUG
        if status == noErr {
            print("[Mic] Set DualSense (device \(deviceID)) as default input device")
        } else {
            print("[Mic] Failed to set DualSense as input: \(status)")
        }
        #endif
    }

    /// Refreshes microphone mute state from the device
    func refreshMicMuteState() {
        guard let deviceID = micDeviceID else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var isMuted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &isMuted)
        if status == noErr {
            self.isMicMuted = isMuted == 1
        }
    }

    /// Applies LED settings to the connected DualSense controller
    func applyLEDSettings(_ settings: DualSenseLEDSettings) {
        storage.lock.lock()
        let isDualSense = storage.isDualSense
        let isBluetooth = storage.isBluetoothConnection
        storage.currentLEDSettings = settings
        storage.lock.unlock()

        guard isDualSense, let device = hidDevice else {
            #if DEBUG
            print("[LED] No DualSense device available (isDualSense=\(isDualSense), hidDevice=\(hidDevice != nil))")
            #endif
            return
        }

        #if DEBUG
        print("[LED] Applying settings via \(isBluetooth ? "Bluetooth" : "USB")")
        #endif
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

        // Set valid_flag2 for LED brightness and lightbar setup control
        report[dataOffset + DualSenseHIDConstants.validFlag2Offset] =
            DualSenseHIDConstants.validFlag2LEDBrightness | DualSenseHIDConstants.validFlag2LightbarSetup

        // Mute button LED (byte 9)
        report[dataOffset + DualSenseHIDConstants.muteButtonLEDOffset] = settings.muteButtonLED.byteValue

        // Player/mute LED brightness (byte 43) - values 0-2
        report[dataOffset + DualSenseHIDConstants.ledBrightnessOffset] = settings.lightBarBrightness.playerLEDBrightness

        // Player LEDs (byte 44)
        report[dataOffset + DualSenseHIDConstants.playerLEDsOffset] = settings.playerLEDs.bitmask

        // Light bar color (bytes 45, 46, 47) - apply brightness multiplier to RGB
        let brightness = UInt16(settings.lightBarBrightness.multiplier)
        report[dataOffset + DualSenseHIDConstants.lightbarRedOffset] = UInt8(UInt16(settings.lightBarColor.redByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarGreenOffset] = UInt8(UInt16(settings.lightBarColor.greenByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarBlueOffset] = UInt8(UInt16(settings.lightBarColor.blueByte) * brightness / 255)

        let result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualSenseHIDConstants.usbOutputReportID),
            report,
            report.count
        )

        #if DEBUG
        if result != kIOReturnSuccess {
            print("Failed to send USB LED report: \(result)")
        }
        #endif
    }

    private func sendBluetoothOutputReport(device: IOHIDDevice, settings: DualSenseLEDSettings) {
        // Build report WITHOUT report ID at position 0 (IOHIDDeviceSetReport takes it separately)
        // Total size is 77 bytes (78 - 1 for report ID)
        var report = [UInt8](repeating: 0, count: DualSenseHIDConstants.bluetoothReportSize - 1)

        // Bluetooth header per Linux kernel hid-playstation.c:
        // - Byte 0: seq_tag = (sequence_number << 4) | tag_field
        // - Byte 1: tag = 0x10 (DS_OUTPUT_TAG)
        report[0] = (bluetoothOutputSeq << 4) | 0x00  // Upper 4 bits = seq number, lower 4 bits = 0
        report[1] = 0x10  // DS_OUTPUT_TAG

        // Increment sequence number (wraps at 16)
        bluetoothOutputSeq = (bluetoothOutputSeq + 1) & 0x0F

        // Data starts at byte 2 (after seq_tag, tag)
        let dataOffset = 2

        // Valid flags - same as USB
        report[dataOffset + 0] = 0xFF  // flag0: enable all
        report[dataOffset + 1] = 0x57  // flag1: 0x01|0x02|0x04|0x10|0x40

        // Set valid_flag2 for LED brightness and lightbar setup control
        report[dataOffset + DualSenseHIDConstants.validFlag2Offset] =
            DualSenseHIDConstants.validFlag2LEDBrightness | DualSenseHIDConstants.validFlag2LightbarSetup

        // Mute button LED (byte 9 from data start)
        report[dataOffset + DualSenseHIDConstants.muteButtonLEDOffset] = settings.muteButtonLED.byteValue

        // Player/mute LED brightness (byte 43 from data start) - values 0-2
        report[dataOffset + DualSenseHIDConstants.ledBrightnessOffset] = settings.lightBarBrightness.playerLEDBrightness

        // Player LEDs (byte 44 from data start)
        report[dataOffset + DualSenseHIDConstants.playerLEDsOffset] = settings.playerLEDs.bitmask

        // Light bar color (bytes 45, 46, 47 from data start) - apply brightness multiplier to RGB
        let brightness = UInt16(settings.lightBarBrightness.multiplier)
        report[dataOffset + DualSenseHIDConstants.lightbarRedOffset] = UInt8(UInt16(settings.lightBarColor.redByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarGreenOffset] = UInt8(UInt16(settings.lightBarColor.greenByte) * brightness / 255)
        report[dataOffset + DualSenseHIDConstants.lightbarBlueOffset] = UInt8(UInt16(settings.lightBarColor.blueByte) * brightness / 255)

        // Calculate CRC32 for Bluetooth (last 4 bytes)
        // CRC is computed over: seed byte (0xA2) + report ID (0x31) + bytes 0-72 of report
        let crcData = Data([0xA2, DualSenseHIDConstants.bluetoothOutputReportID] + report[0..<73])
        let crc = crc32(crcData)
        report[73] = UInt8(crc & 0xFF)
        report[74] = UInt8((crc >> 8) & 0xFF)
        report[75] = UInt8((crc >> 16) & 0xFF)
        report[76] = UInt8((crc >> 24) & 0xFF)

        #if DEBUG
        // Debug: print first 10 bytes of report
        let headerBytes = report[0..<10].map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[LED] BT Report (no ID): \(headerBytes), seq=\((bluetoothOutputSeq + 15) & 0x0F)")
        #endif

        // Try Output Report first
        var result = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualSenseHIDConstants.bluetoothOutputReportID),
            report,
            report.count
        )

        #if DEBUG
        if result == kIOReturnSuccess {
            print("[LED] Bluetooth output report sent successfully")
        } else {
            print("[LED] Output report failed (\(String(format: "0x%08X", result))), trying feature report...")
        }
        #endif

        if result != kIOReturnSuccess {
            // Try Feature Report as fallback (some macOS Bluetooth implementations handle these differently)
            result = IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeFeature,
                CFIndex(DualSenseHIDConstants.bluetoothOutputReportID),
                report,
                report.count
            )

            #if DEBUG
            if result == kIOReturnSuccess {
                print("[LED] Bluetooth feature report sent successfully")
            } else {
                print("[LED] Failed to send Bluetooth LED report: \(String(format: "0x%08X", result))")
            }
            #endif
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

    // MARK: - Party Mode

    func setPartyMode(_ enabled: Bool, savedSettings: DualSenseLEDSettings) {
        if enabled {
            startPartyMode()
        } else {
            stopPartyMode(restoreSettings: savedSettings)
        }
        partyModeEnabled = enabled
    }

    private func startPartyMode() {
        partyHue = 0.0
        partyLEDIndex = 0
        partyLEDDirection = 1

        partyModeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePartyMode()
            }
        }
    }

    private func stopPartyMode(restoreSettings: DualSenseLEDSettings) {
        partyModeTimer?.invalidate()
        partyModeTimer = nil
        applyLEDSettings(restoreSettings)
    }

    private func updatePartyMode() {
        guard partyModeEnabled else { return }

        partyHue += 0.005
        if partyHue >= 1.0 {
            partyHue = 0.0
        }

        let frameCount = Int(partyHue * 200) % 15
        if frameCount == 0 {
            partyLEDIndex += partyLEDDirection
            if partyLEDIndex >= partyLEDPatterns.count - 1 {
                partyLEDDirection = -1
            } else if partyLEDIndex <= 0 {
                partyLEDDirection = 1
            }
        }

        let rainbowColor = Color(hue: partyHue, saturation: 1.0, brightness: 1.0)
        var partySettings = DualSenseLEDSettings()
        partySettings.lightBarEnabled = true
        partySettings.lightBarColor = CodableColor(color: rainbowColor)
        partySettings.lightBarBrightness = .bright
        partySettings.muteButtonLED = .breathing
        partySettings.playerLEDs = partyLEDPatterns[max(0, min(partyLEDIndex, partyLEDPatterns.count - 1))]

        applyLEDSettings(partySettings)
    }

    // MARK: - Keep Alive

    func setKeepAlive(_ enabled: Bool) {
        keepAliveEnabled = enabled
        if enabled {
            startKeepAlive()
        } else {
            stopKeepAlive()
        }
    }

    private func startKeepAlive() {
        stopKeepAlive()  // Cancel any existing timer

        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: keepAliveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendKeepAliveSignal()
            }
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    private func sendKeepAliveSignal() {
        guard keepAliveEnabled, let device = hidDevice, isBluetoothConnection else { return }

        // Send a minimal output report to reset the controller's idle timer
        // This uses the same mechanism as LED updates but with minimal data
        var report = [UInt8](repeating: 0, count: DualSenseHIDConstants.bluetoothReportSize - 1)

        // Bluetooth header
        report[0] = (bluetoothOutputSeq << 4) | 0x00
        report[1] = 0x10  // DS_OUTPUT_TAG

        // Increment sequence number
        bluetoothOutputSeq = (bluetoothOutputSeq + 1) & 0x0F

        // Minimal valid flags - just enough to be accepted
        let dataOffset = 2
        report[dataOffset + 0] = 0x00  // No motor/haptic updates
        report[dataOffset + 1] = 0x00  // No LED updates

        // Calculate CRC32
        let crcData = Data([0xA2, DualSenseHIDConstants.bluetoothOutputReportID] + report[0..<73])
        let crc = crc32(crcData)
        report[73] = UInt8(crc & 0xFF)
        report[74] = UInt8((crc >> 8) & 0xFF)
        report[75] = UInt8((crc >> 16) & 0xFF)
        report[76] = UInt8((crc >> 24) & 0xFF)

        // Send output report
        _ = IOHIDDeviceSetReport(
            device,
            kIOHIDReportTypeOutput,
            CFIndex(DualSenseHIDConstants.bluetoothOutputReportID),
            report,
            report.count
        )

        #if DEBUG
        print("[KeepAlive] Sent keep-alive signal")
        #endif
    }

    nonisolated private func handleHIDReport(reportID: UInt32, report: UnsafeMutablePointer<UInt8>, length: Int) {
        // Process report 0x31 (Bluetooth) or 0x01 (USB) input reports
        // USB report 0x01: buttons at different offsets (no extra header byte)
        // Bluetooth report 0x31: has extra header, buttons2 at byte 11
        let buttons2Offset: Int
        if reportID == 0x31 && length >= 12 {
            buttons2Offset = 11  // Bluetooth
        } else if reportID == 0x01 && length >= 11 {
            buttons2Offset = 10  // USB (one byte less offset)
        } else {
            return
        }

        // buttons2 contains PS/Touch/Mute and Edge paddles
        // Bit 0: PS button, Bit 1: Touchpad button, Bit 2: Mic mute
        // DualSense Edge additional buttons (bits 4-7):
        // Bit 4: Left function (0x10), Bit 5: Right function (0x20)
        // Bit 6: Left paddle (0x40), Bit 7: Right paddle (0x80)
        let buttons2 = report[buttons2Offset]
        let psPressed = (buttons2 & 0x01) != 0
        let micPressed = (buttons2 & 0x04) != 0

        // DualSense Edge buttons
        let leftFnPressed = (buttons2 & 0x10) != 0
        let rightFnPressed = (buttons2 & 0x20) != 0
        let leftPaddlePressed = (buttons2 & 0x40) != 0
        let rightPaddlePressed = (buttons2 & 0x80) != 0

        // Detect state changes (thread-safe)
        storage.lock.lock()
        let psChanged = psPressed != storage.lastPSButtonState
        let micChanged = micPressed != storage.lastMicButtonState
        let isEdge = storage.isDualSenseEdge

        // Edge button state changes
        let leftFnChanged = leftFnPressed != storage.lastLeftFunctionState
        let rightFnChanged = rightFnPressed != storage.lastRightFunctionState
        let leftPaddleChanged = leftPaddlePressed != storage.lastLeftPaddleState
        let rightPaddleChanged = rightPaddlePressed != storage.lastRightPaddleState

        if psChanged {
            storage.lastPSButtonState = psPressed
        }
        if micChanged {
            storage.lastMicButtonState = micPressed
        }
        if leftFnChanged {
            storage.lastLeftFunctionState = leftFnPressed
        }
        if rightFnChanged {
            storage.lastRightFunctionState = rightFnPressed
        }
        if leftPaddleChanged {
            storage.lastLeftPaddleState = leftPaddlePressed
        }
        if rightPaddleChanged {
            storage.lastRightPaddleState = rightPaddlePressed
        }
        storage.lock.unlock()

        if psChanged {
            controllerQueue.async { [weak self] in
                self?.handleButton(.xbox, pressed: psPressed)
            }
        }
        if micChanged {
            controllerQueue.async { [weak self] in
                self?.handleButton(.micMute, pressed: micPressed)
            }
        }

        // Only process Edge buttons if this is actually an Edge controller
        if isEdge {
            if leftFnChanged {
                controllerQueue.async { [weak self] in
                    self?.handleButton(.leftFunction, pressed: leftFnPressed)
                }
            }
            if rightFnChanged {
                controllerQueue.async { [weak self] in
                    self?.handleButton(.rightFunction, pressed: rightFnPressed)
                }
            }
            if leftPaddleChanged {
                controllerQueue.async { [weak self] in
                    self?.handleButton(.leftPaddle, pressed: leftPaddlePressed)
                }
            }
            if rightPaddleChanged {
                controllerQueue.async { [weak self] in
                    self?.handleButton(.rightPaddle, pressed: rightPaddlePressed)
                }
            }
        }
    }

    // MARK: - Thread-Safe Update Helpers
    
    nonisolated private func updateLeftStick(x: Float, y: Float) {
        storage.lock.lock()
        storage.leftStick = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let callback = storage.onLeftStickMoved
        storage.lock.unlock()

        // Only create Task if callback exists (avoids creating 250+ Tasks/sec for nil callbacks)
        if let callback = callback {
            let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
            Task { @MainActor in
                callback(point)
            }
        }
    }

    nonisolated private func updateRightStick(x: Float, y: Float) {
        storage.lock.lock()
        storage.rightStick = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let callback = storage.onRightStickMoved
        storage.lock.unlock()

        // Only create Task if callback exists (avoids creating 250+ Tasks/sec for nil callbacks)
        if let callback = callback {
            let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
            Task { @MainActor in
                callback(point)
            }
        }
    }

    /// Computes a two-finger gesture using the shared center point.
    /// Requires storage.lock to be held by the caller.
    nonisolated private func computeTwoFingerGestureLocked(secondaryFresh: Bool) -> TouchpadGesture? {
        guard storage.isTouchpadTouching, storage.isTouchpadSecondaryTouching, secondaryFresh else {
            storage.touchpadGestureHasCenter = false
            return nil
        }

        let distance = hypot(
            storage.touchpadPosition.x - storage.touchpadSecondaryPosition.x,
            storage.touchpadPosition.y - storage.touchpadSecondaryPosition.y
        )
        guard Double(distance) > Config.touchpadTwoFingerMinDistance else {
            storage.touchpadGestureHasCenter = false
            return nil
        }

        let currentCenter = CGPoint(
            x: (storage.touchpadPosition.x + storage.touchpadSecondaryPosition.x) * 0.5,
            y: (storage.touchpadPosition.y + storage.touchpadSecondaryPosition.y) * 0.5
        )
        let currentDistance = Double(distance)

        if !storage.touchpadGestureHasCenter {
            storage.touchpadGestureHasCenter = true
            storage.touchpadGesturePreviousCenter = currentCenter
            storage.touchpadGesturePreviousDistance = currentDistance
            return TouchpadGesture(
                centerDelta: .zero,
                distanceDelta: 0,
                isPrimaryTouching: storage.isTouchpadTouching,
                isSecondaryTouching: storage.isTouchpadSecondaryTouching
            )
        }

        let previousCenter = storage.touchpadGesturePreviousCenter
        let previousDistance = storage.touchpadGesturePreviousDistance
        let centerDelta = CGPoint(
            x: currentCenter.x - previousCenter.x,
            y: currentCenter.y - previousCenter.y
        )
        let distanceDelta = currentDistance - previousDistance

        storage.touchpadGesturePreviousCenter = currentCenter
        storage.touchpadGesturePreviousDistance = currentDistance
        storage.touchpadTwoFingerGestureDistance += hypot(Double(centerDelta.x), Double(centerDelta.y))
        storage.touchpadTwoFingerPinchDistance += abs(distanceDelta)

        return TouchpadGesture(
            centerDelta: centerDelta,
            distanceDelta: distanceDelta,
            isPrimaryTouching: storage.isTouchpadTouching,
            isSecondaryTouching: storage.isTouchpadSecondaryTouching
        )
    }

    // MARK: - Primary Touchpad Handler

    /// Handles primary touchpad finger input. This is a state machine with three main states:
    /// 1. Touch Start: Initialize position tracking and start long tap timer
    /// 2. Touch Continue: Calculate deltas, detect gestures, handle tap cooldowns
    /// 3. Touch End: Detect taps, cleanup state, fire callbacks
    nonisolated private func updateTouchpad(x: Float, y: Float) {
        defer { logTouchpadDebugIfNeeded(source: "primary") }
        storage.lock.lock()

        // MARK: Initial Setup
        let newPosition = CGPoint(x: CGFloat(x), y: CGFloat(y))
        let wasTouching = storage.isTouchpadTouching
        let wasTwoFinger = storage.isTouchpadTouching && storage.isTouchpadSecondaryTouching
        let gestureCallback = storage.onTouchpadGesture
        let now = CFAbsoluteTimeGetCurrent()
        let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
        // Secondary finger block is handled by secondaryFresh checks below.

        // MARK: Sentinel-based Touch Detection
        // Detect if finger is on touchpad (non-zero position indicates touch)
        // GCControllerDirectionPad returns 0,0 when no finger is present
        var isTouching = abs(x) > 0.001 || abs(y) > 0.001
        if !storage.touchpadHasSeenTouch, isTouching {
            if let sentinel = storage.touchpadIdleSentinel {
                let isNearSentinel = abs(newPosition.x - sentinel.x) <= TouchpadIdleSentinelConfig.activationThreshold &&
                    abs(newPosition.y - sentinel.y) <= TouchpadIdleSentinelConfig.activationThreshold
                if isNearSentinel {
                    isTouching = false
                } else {
                    storage.touchpadHasSeenTouch = true
                    storage.touchpadIdleSentinel = nil
                }
            } else {
                storage.touchpadIdleSentinel = newPosition
                isTouching = false
            }
        }
        if isTouching {
            storage.touchpadHasSeenTouch = true
        }

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
                    if secondaryFresh {
                        storage.touchpadPreviousPosition = storage.touchpadPosition
                    } else {
                        storage.touchpadPreviousPosition = newPosition
                    }
                    storage.touchpadPosition = newPosition
                    let gesture = computeTwoFingerGestureLocked(secondaryFresh: secondaryFresh)
                    let gestureCallback = storage.onTouchpadGesture
                    storage.lock.unlock()

                    if let gesture {
                        gestureCallback?(gesture)
                    }
                    return
                }

                // Increment frame counter
                storage.touchpadFramesSinceTouch += 1

                // Skip first 2 frames after touch to let position settle
                // This prevents spurious movement when finger first contacts touchpad
                // Update touchStartPosition so the settle check uses the stable position
                // (the initial touch position from hardware can be noisy/incorrect)
                // NOTE: Do NOT update touchpadTouchStartTime - keep counting from original touch
                if storage.touchpadFramesSinceTouch <= 2 {
                    storage.touchpadPosition = newPosition
                    storage.touchpadPreviousPosition = newPosition
                    storage.touchpadTouchStartPosition = newPosition
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

                // Track max distance from start for tap detection
                let currentDistance = Double(hypot(
                    newPosition.x - storage.touchpadTouchStartPosition.x,
                    newPosition.y - storage.touchpadTouchStartPosition.y
                ))
                if currentDistance > storage.touchpadMaxDistanceFromStart {
                    storage.touchpadMaxDistanceFromStart = currentDistance
                    // Cancel long tap timer if finger moved too much (uses tighter threshold)
                    if currentDistance >= Config.touchpadLongTapMaxMovement {
                        storage.touchpadLongTapTimer?.cancel()
                        storage.touchpadLongTapTimer = nil
                    }
                }

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

                let gesture = computeTwoFingerGestureLocked(secondaryFresh: secondaryFresh)

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
                storage.touchpadGestureHasCenter = false
                storage.touchpadGesturePreviousCenter = .zero
                storage.touchpadGesturePreviousDistance = 0
                storage.touchpadFramesSinceTouch = 0
                storage.pendingTouchpadDelta = nil
                storage.touchpadTouchStartTime = now
                storage.touchpadTouchStartPosition = newPosition
                storage.touchpadMaxDistanceFromStart = 0
                // Check if secondary is already touching (for two-finger tap detection)
                let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
                storage.touchpadWasTwoFingerDuringTouch = secondaryFresh
                storage.touchpadTwoFingerGestureDistance = 0  // Reset for new touch session
                storage.touchpadTwoFingerPinchDistance = 0
                // Block movement if this touch starts within cooldown of a previous tap
                // This prevents double-tap from causing mouse movement between taps
                if (now - storage.touchpadLastTapTime) < Config.touchpadTapCooldown {
                    storage.touchpadMovementBlocked = true
                }
                if storage.touchpadClickArmed {
                    storage.touchpadClickStartPosition = newPosition
                }
                // Cancel any existing long tap timer and reset state
                storage.touchpadLongTapTimer?.cancel()
                storage.touchpadLongTapTimer = nil
                storage.touchpadLongTapFired = false

                // Start long tap timer
                let longTapCallback = secondaryFresh ? storage.onTouchpadTwoFingerLongTap : storage.onTouchpadLongTap
                if longTapCallback != nil {
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        self.storage.lock.lock()
                        // Only fire if finger hasn't moved too much
                        let distance = self.storage.touchpadMaxDistanceFromStart
                        let stillTouching = self.storage.isTouchpadTouching
                        let isTwoFinger = self.storage.touchpadWasTwoFingerDuringTouch
                        let callback = isTwoFinger ? self.storage.onTouchpadTwoFingerLongTap : self.storage.onTouchpadLongTap
                        if stillTouching && distance < Config.touchpadLongTapMaxMovement {
                            self.storage.touchpadLongTapFired = true
                            self.storage.lock.unlock()
                            self.controllerQueue.async { callback?() }
                        } else {
                            self.storage.lock.unlock()
                        }
                    }
                    storage.touchpadLongTapTimer = workItem
                    controllerQueue.asyncAfter(deadline: .now() + Config.touchpadLongTapThreshold, execute: workItem)
                }
                storage.lock.unlock()
            }
        } else {
            // Finger lifted - discard any pending delta (it was likely lift artifact)
            // Cancel long tap timer
            storage.touchpadLongTapTimer?.cancel()
            storage.touchpadLongTapTimer = nil
            storage.touchpadGestureHasCenter = false
            storage.touchpadGesturePreviousCenter = .zero
            storage.touchpadGesturePreviousDistance = 0
            let longTapFired = storage.touchpadLongTapFired

            // Check for tap: short touch duration with minimal movement
            // Use maxDistanceFromStart instead of final position (which may be corrupted by lift artifacts)
            let touchDuration = now - storage.touchpadTouchStartTime
            let touchDistance = storage.touchpadMaxDistanceFromStart
            let wasTwoFingerDuringTouch = storage.touchpadWasTwoFingerDuringTouch
            let clickFiredDuringTouch = storage.touchpadClickFiredDuringTouch

            // Single-finger tap: short duration, minimal movement, NOT a two-finger gesture,
            // long tap not fired, and no physical click during this touch
            let isSingleTap = wasTouching &&
                !wasTwoFingerDuringTouch &&
                !longTapFired &&
                !clickFiredDuringTouch &&
                touchDuration < Config.touchpadTapMaxDuration &&
                touchDistance < Config.touchpadTapMaxMovement
            let tapCallback = isSingleTap ? storage.onTouchpadTap : nil

            // Two-finger tap: both fingers had short duration and minimal movement, long tap not fired,
            // and no physical click during this touch
            // Secondary finger uses more lenient threshold due to touchpad noise
            // Also check that there wasn't significant gesture (scroll/pinch) movement
            let secondaryTouchDuration = now - storage.touchpadSecondaryTouchStartTime
            let secondaryTouchDistance = storage.touchpadSecondaryMaxDistanceFromStart
            let gestureDistance = storage.touchpadTwoFingerGestureDistance
            let pinchDistance = storage.touchpadTwoFingerPinchDistance
            let isTwoFingerTap = wasTwoFingerDuringTouch &&
                !longTapFired &&
                !clickFiredDuringTouch &&
                touchDuration < Config.touchpadTapMaxDuration &&
                touchDistance < Config.touchpadTapMaxMovement &&
                secondaryTouchDuration < Config.touchpadTapMaxDuration &&
                secondaryTouchDistance < Config.touchpadTwoFingerTapMaxMovement &&
                gestureDistance < Config.touchpadTwoFingerTapMaxGestureDistance &&
                pinchDistance < Config.touchpadTwoFingerTapMaxPinchDistance
            let twoFingerTapCallback = isTwoFingerTap ? storage.onTouchpadTwoFingerTap : nil

            if isSingleTap || isTwoFingerTap {
                storage.touchpadLastTapTime = now
            }

            storage.isTouchpadTouching = false
            storage.touchpadPosition = .zero
            storage.touchpadPreviousPosition = .zero
            storage.touchpadFramesSinceTouch = 0
            storage.pendingTouchpadDelta = nil
            storage.touchpadClickArmed = false
            storage.touchpadClickFiredDuringTouch = false
            storage.touchpadMovementBlocked = false
            storage.touchpadLongTapFired = false
            let isSecondaryTouching = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
            let isTwoFinger = storage.isTouchpadTouching && isSecondaryTouching
            storage.lock.unlock()

            // Fire tap callback if it was a tap (not if long tap was fired)
            tapCallback?()
            twoFingerTapCallback?()

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
        var isTouching = abs(x) > 0.001 || abs(y) > 0.001
        if !storage.touchpadSecondaryHasSeenTouch, isTouching {
            if let sentinel = storage.touchpadSecondaryIdleSentinel {
                let isNearSentinel = abs(newPosition.x - sentinel.x) <= TouchpadIdleSentinelConfig.activationThreshold &&
                    abs(newPosition.y - sentinel.y) <= TouchpadIdleSentinelConfig.activationThreshold
                if isNearSentinel {
                    isTouching = false
                } else {
                    storage.touchpadSecondaryHasSeenTouch = true
                    storage.touchpadSecondaryIdleSentinel = nil
                }
            } else {
                storage.touchpadSecondaryIdleSentinel = newPosition
                isTouching = false
            }
        }
        if isTouching {
            storage.touchpadSecondaryHasSeenTouch = true
        }

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

                // Track max distance from start for two-finger tap detection
                let distanceFromStart = hypot(
                    Double(newPosition.x - storage.touchpadSecondaryTouchStartPosition.x),
                    Double(newPosition.y - storage.touchpadSecondaryTouchStartPosition.y)
                )
                storage.touchpadSecondaryMaxDistanceFromStart = max(storage.touchpadSecondaryMaxDistanceFromStart, distanceFromStart)
            } else {
                // Finger just touched - initialize position and tracking for two-finger tap
                storage.touchpadSecondaryPosition = newPosition
                storage.touchpadSecondaryPreviousPosition = newPosition
                storage.isTouchpadSecondaryTouching = true
                storage.touchpadGestureHasCenter = false
                storage.touchpadGesturePreviousCenter = .zero
                storage.touchpadGesturePreviousDistance = 0
                storage.touchpadSecondaryFramesSinceTouch = 0
                storage.touchpadSecondaryLastUpdate = now
                storage.touchpadSecondaryLastTouchTime = now
                storage.touchpadSecondaryTouchStartTime = now
                storage.touchpadSecondaryTouchStartPosition = newPosition
                storage.touchpadSecondaryMaxDistanceFromStart = 0
                let isPrimaryTouching = storage.isTouchpadTouching
                // Mark that two fingers touched during this primary touch session
                if isPrimaryTouching {
                    storage.touchpadWasTwoFingerDuringTouch = true
                }
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

            let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
            let gesture = computeTwoFingerGestureLocked(secondaryFresh: secondaryFresh)
            storage.lock.unlock()
            if let gesture {
                gestureCallback?(gesture)
            }
        } else {
            storage.isTouchpadSecondaryTouching = false
            storage.touchpadSecondaryPosition = .zero
            storage.touchpadSecondaryPreviousPosition = .zero
            storage.touchpadSecondaryFramesSinceTouch = 0
            storage.touchpadSecondaryLastUpdate = now
            storage.touchpadGestureHasCenter = false
            storage.touchpadGesturePreviousCenter = .zero
            storage.touchpadGesturePreviousDistance = 0
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

        #if DEBUG
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
        #endif
    }

    /// Arms/disarms touchpad click and detects two-finger clicks.
    /// Returns true if this is a two-finger click (on release), in which case the normal button handling should be suppressed.
    nonisolated private func armTouchpadClick(pressed: Bool) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        storage.lock.lock()
        if pressed {
            storage.touchpadClickArmed = true
            storage.touchpadClickStartPosition = storage.touchpadPosition
            storage.touchpadClickFiredDuringTouch = true  // Suppress tap when touch ends
            storage.pendingTouchpadDelta = nil
            storage.touchpadFramesSinceTouch = 0

            // Check if two fingers are on the touchpad
            let isPrimaryTouching = storage.isTouchpadTouching
            let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
            let isTwoFinger = isPrimaryTouching && secondaryFresh
            storage.touchpadTwoFingerClickArmed = isTwoFinger
            storage.lock.unlock()
            return false  // On press, don't suppress yet
        } else {
            storage.touchpadClickArmed = false
            let wasTwoFingerClick = storage.touchpadTwoFingerClickArmed
            storage.touchpadTwoFingerClickArmed = false
            storage.lock.unlock()
            return wasTwoFingerClick  // On release, return whether to suppress normal handling
        }
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
    nonisolated func playHaptic(intensity: Float = 0.5, sharpness: Float = 0.5, duration: TimeInterval = 0.1, transient: Bool = false) {
        hapticQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.hapticEngines.isEmpty else { return }

            // Prune expired players to avoid truncating overlapping haptics
            let now = CFAbsoluteTimeGetCurrent()
            self.activeHapticPlayers.removeAll { $0.endTime <= now }

            do {
                let event: CHHapticEvent
                if transient {
                    // Transient: single-shot pulse, more reliable for brief feedback
                    event = CHHapticEvent(
                        eventType: .hapticTransient,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                        ],
                        relativeTime: 0
                    )
                } else {
                    // Continuous: sustained haptic for longer feedback
                    event = CHHapticEvent(
                        eventType: .hapticContinuous,
                        parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                        ],
                        relativeTime: 0,
                        duration: duration
                    )
                }
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let estimatedDuration = transient ? max(duration, 0.06) : max(duration, 0.01)
                let endTime = CFAbsoluteTimeGetCurrent() + estimatedDuration + 0.02

                // Play on all available engines for maximum effect
                // Retain players so they aren't deallocated before playback completes
                for engine in self.hapticEngines {
                    do {
                        let player = try engine.makePlayer(with: pattern)
                        self.activeHapticPlayers.append(ActiveHapticPlayer(player: player, endTime: endTime))
                        try player.start(atTime: CHHapticTimeImmediate)
                    } catch {
                        // Try to restart engine and retry once
                        try? engine.start()
                        if let player = try? engine.makePlayer(with: pattern) {
                            self.activeHapticPlayers.append(ActiveHapticPlayer(player: player, endTime: endTime))
                            try? player.start(atTime: CHHapticTimeImmediate)
                        }
                    }
                }
                if self.activeHapticPlayers.count > 12 {
                    self.activeHapticPlayers.removeFirst(self.activeHapticPlayers.count - 12)
                }
            } catch {
                // Haptic pattern error, continue silently
            }
        }
    }

    // MARK: - Test Helpers
    #if DEBUG
    /// Sets the left stick value for testing (bypasses controller input)
    nonisolated func setLeftStickForTesting(_ value: CGPoint) {
        storage.lock.lock()
        storage.leftStick = value
        storage.lock.unlock()
    }

    /// Sets the right stick value for testing (bypasses controller input)
    nonisolated func setRightStickForTesting(_ value: CGPoint) {
        storage.lock.lock()
        storage.rightStick = value
        storage.lock.unlock()
    }
    #endif
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
