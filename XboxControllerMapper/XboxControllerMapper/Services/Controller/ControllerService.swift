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

// MARK: - Thread-Safe Input State (High Performance)

final class ControllerStorage: @unchecked Sendable {
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
    var isDualShock: Bool = false  // PS4 DualShock 4 controller
    var isBluetoothConnection: Bool = false
    var lastInputTime: TimeInterval = 0
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

    // Motion Gesture State (DualSense gyroscope)
    var motionGestureDetector = MotionGestureDetector()
    var onMotionGesture: ((MotionGestureType) -> Void)?

    // Gyro aiming: accumulated rotation rates between polls (averaged on consume)
    var motionPitchAccum: Double = 0
    var motionRollAccum: Double = 0
    var motionSampleCount: Int = 0
}

/// Service for managing game controller connection and input
@MainActor
class ControllerService: ObservableObject {
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @Published var isConnected = false
    @Published var connectedController: GCController?
    @Published var controllerName: String = ""

    /// Currently pressed buttons (UI use only, updated asynchronously)
    @Published var activeButtons: Set<ControllerButton> = []

    /// Party mode state
    @Published var partyModeEnabled = false

    /// Whether the current connection is Bluetooth (for UI display)
    @Published var isBluetoothConnection = false

    /// Microphone state
    @Published var isMicMuted = false
    @Published var micAudioLevel: Float = 0.0
    var micDeviceID: AudioDeviceID?
    var micLevelTimer: Timer?
    var audioEngine: AVAudioEngine?

    var batteryBlinkTimer: Timer?
    var batteryBlinkOn: Bool = true

    var partyModeTimer: Timer?
    var partyHue: Double = 0.0
    var partyLEDIndex: Int = 0
    var partyLEDDirection: Int = 1

    let partyLEDPatterns: [PlayerLEDs] = [
        PlayerLEDs(led1: false, led2: false, led3: true, led4: false, led5: false),
        PlayerLEDs(led1: false, led2: true, led3: false, led4: true, led5: false),
        PlayerLEDs(led1: true, led2: false, led3: false, led4: false, led5: true),
        PlayerLEDs(led1: true, led2: true, led3: false, led4: true, led5: true),
        PlayerLEDs(led1: true, led2: true, led3: true, led4: true, led5: true),
    ]

    let controllerQueue = DispatchQueue(label: "com.xboxmapper.controller", qos: .userInteractive)
    let storage = ControllerStorage()

    // HID monitoring for DualSense mic button (not exposed by GameController framework)
    var hidManager: IOHIDManager?
    var hidReportBuffer: UnsafeMutablePointer<UInt8>?
    var hidDevice: IOHIDDevice?
    var bluetoothOutputSeq: UInt8 = 0  // Sequence number for Bluetooth output reports (0-15)
    var keepAliveTimer: DispatchSourceTimer?

    // Generic HID controller fallback (for controllers not recognized by GameController framework)
    var genericHIDManager: IOHIDManager?
    var genericHIDController: GenericHIDController?
    var genericHIDFallbackTimer: DispatchWorkItem?
    @Published var isGenericController = false

    /// Retained context pointer for generic HID callbacks — released in cleanupGenericHIDMonitoring().
    var genericHIDCallbackContext: UnsafeMutableRawPointer?

    /// Retained context pointer for PlayStation HID report callback — released in cleanupHIDMonitoring().
    var psHIDCallbackContext: UnsafeMutableRawPointer?

    enum TouchpadIdleSentinelConfig {
        static let activationThreshold: CGFloat = 0.02
    }

    nonisolated func withStorageLock<T>(_ operation: (ControllerStorage) -> T) -> T {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return operation(storage)
    }

    nonisolated func readStorage<T>(_ keyPath: KeyPath<ControllerStorage, T>) -> T {
        withStorageLock { $0[keyPath: keyPath] }
    }

    nonisolated func writeStorage<T>(
        _ keyPath: ReferenceWritableKeyPath<ControllerStorage, T>,
        _ value: T
    ) {
        withStorageLock { $0[keyPath: keyPath] = value }
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

    nonisolated var threadSafeIsTouchpadButtonPressed: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.touchpadClickArmed
    }

    nonisolated var threadSafeIsTouchpadMovementBlocked: Bool {
        storage.lock.lock()
        // Capture timestamp INSIDE the lock so it is consistent with the
        // touchpadSecondaryLastTouchTime read. Reading `now` before locking
        // creates a race where another thread updates the touch time between
        // our timestamp capture and the lock acquisition.
        let now = CFAbsoluteTimeGetCurrent()
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

    nonisolated var threadSafeIsDualShock: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isDualShock
    }

    /// Returns true if connected controller is any PlayStation controller (DualSense, DualShock)
    nonisolated var threadSafeIsPlayStation: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isDualSense || storage.isDualShock
    }

    /// Returns the average gyro rotation rates accumulated since the last call, then resets the accumulator.
    nonisolated func consumeAverageMotionRates() -> (pitch: Double, roll: Double) {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        let count = storage.motionSampleCount
        guard count > 0 else { return (0, 0) }
        let pitch = storage.motionPitchAccum / Double(count)
        let roll = storage.motionRollAccum / Double(count)
        storage.motionPitchAccum = 0
        storage.motionRollAccum = 0
        storage.motionSampleCount = 0
        return (pitch, roll)
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

    nonisolated var threadSafeChordWindow: TimeInterval {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.chordWindow
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
        get { readStorage(\.chordWindow) }
        set { writeStorage(\.chordWindow, newValue) }
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
        get { readStorage(\.onButtonPressed) }
        set { writeStorage(\.onButtonPressed, newValue) }
    }
    var onButtonReleased: ((ControllerButton, TimeInterval) -> Void)? {
        get { readStorage(\.onButtonReleased) }
        set { writeStorage(\.onButtonReleased, newValue) }
    }
    var onChordDetected: ((Set<ControllerButton>) -> Void)? {
        get { readStorage(\.onChordDetected) }
        set { writeStorage(\.onChordDetected, newValue) }
    }
    var onLeftStickMoved: ((CGPoint) -> Void)? {
        get { readStorage(\.onLeftStickMoved) }
        set { writeStorage(\.onLeftStickMoved, newValue) }
    }
    var onRightStickMoved: ((CGPoint) -> Void)? {
        get { readStorage(\.onRightStickMoved) }
        set { writeStorage(\.onRightStickMoved, newValue) }
    }
    var onTouchpadMoved: ((CGPoint) -> Void)? {
        get { readStorage(\.onTouchpadMoved) }
        set { writeStorage(\.onTouchpadMoved, newValue) }
    }
    var onTouchpadGesture: ((TouchpadGesture) -> Void)? {
        get { readStorage(\.onTouchpadGesture) }
        set { writeStorage(\.onTouchpadGesture, newValue) }
    }
    var onTouchpadTap: (() -> Void)? {
        get { readStorage(\.onTouchpadTap) }
        set { writeStorage(\.onTouchpadTap, newValue) }
    }
    var onTouchpadTwoFingerTap: (() -> Void)? {
        get { readStorage(\.onTouchpadTwoFingerTap) }
        set { writeStorage(\.onTouchpadTwoFingerTap, newValue) }
    }
    var onTouchpadLongTap: (() -> Void)? {
        get { readStorage(\.onTouchpadLongTap) }
        set { writeStorage(\.onTouchpadLongTap, newValue) }
    }
    var onTouchpadTwoFingerLongTap: (() -> Void)? {
        get { readStorage(\.onTouchpadTwoFingerLongTap) }
        set { writeStorage(\.onTouchpadTwoFingerLongTap, newValue) }
    }
    var onMotionGesture: ((MotionGestureType) -> Void)? {
        get { readStorage(\.onMotionGesture) }
        set { writeStorage(\.onMotionGesture, newValue) }
    }

    private var cancellables = Set<AnyCancellable>()

    // Low-level monitor for Xbox Guide button
    private let guideMonitor = XboxGuideMonitor()

    // Low-level monitor for Battery (Bluetooth Workaround for macOS/Xbox issue)
    private let batteryMonitor = BluetoothBatteryMonitor()

    // Haptic engines for controller feedback (try multiple localities)
    var hapticEngines: [CHHapticEngine] = []
    let hapticQueue = DispatchQueue(label: "com.xboxmapper.haptic", qos: .userInitiated)
    struct ActiveHapticPlayer {
        let player: CHHapticPatternPlayer
        let endTime: TimeInterval
    }
    var activeHapticPlayers: [ActiveHapticPlayer] = []

    init(enableHardwareMonitoring: Bool = true) {
        let shouldEnableHardwareMonitoring = enableHardwareMonitoring && !Self.isRunningTests

        // Load last controller type (so UI shows correct button labels when no controller is connected)
        storage.isDualSense = UserDefaults.standard.bool(forKey: Config.lastControllerWasDualSenseKey)
        storage.isDualSenseEdge = UserDefaults.standard.bool(forKey: Config.lastControllerWasDualSenseEdgeKey)
        storage.isDualShock = UserDefaults.standard.bool(forKey: Config.lastControllerWasDualShockKey)

        if shouldEnableHardwareMonitoring {
            GCController.shouldMonitorBackgroundEvents = true
            setupNotifications()
            startDiscovery()
            checkConnectedControllers()
            batteryMonitor.startMonitoring()
            batteryMonitor.$batteryLevel
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.updateBatteryInfo()
                }
                .store(in: &cancellables)

            setupGenericHIDMonitoring()
        }

        guideMonitor.onGuideButtonAction = { [weak self] isPressed in
            guard let self = self else { return }
            self.controllerQueue.async {
                self.handleButton(.xbox, pressed: isPressed)
            }
        }
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

    func controllerDisconnected() {
        // Disable motion sensors before disconnecting
        connectedController?.motion?.sensorsActive = false
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
        stopKeepAliveTimer()
        stopBatteryBlink()
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
        resetMotionStateLocked()
        storage.lastMicButtonState = false
        storage.lock.unlock()
    }

    func resetTouchpadStateLocked() {
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

    // MARK: - Display Update Timer

    func startDisplayUpdateTimer() {
        stopDisplayUpdateTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: Config.displayRefreshInterval, leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }

            // Touchpad samples are not exposed via dedicated thread-safe accessors.
            self.storage.lock.lock()
            let touchPos = self.storage.touchpadPosition
            let touchSecPos = self.storage.touchpadSecondaryPosition
            let isTouching = self.storage.isTouchpadTouching
            let isSecTouching = self.storage.isTouchpadSecondaryTouching
            self.storage.lock.unlock()

            let currentState = ControllerDisplayState(
                leftStick: self.leftStick,
                rightStick: self.rightStick,
                leftTriggerValue: self.leftTriggerValue,
                rightTriggerValue: self.rightTriggerValue,
                displayLeftStick: self.displayLeftStick,
                displayRightStick: self.displayRightStick,
                displayLeftTrigger: self.displayLeftTrigger,
                displayRightTrigger: self.displayRightTrigger,
                displayTouchpadPosition: self.displayTouchpadPosition,
                displayTouchpadSecondaryPosition: self.displayTouchpadSecondaryPosition,
                displayIsTouchpadTouching: self.displayIsTouchpadTouching,
                displayIsTouchpadSecondaryTouching: self.displayIsTouchpadSecondaryTouching
            )
            let sample = ControllerDisplaySample(
                leftStick: self.threadSafeLeftStick,
                rightStick: self.threadSafeRightStick,
                leftTrigger: self.threadSafeLeftTrigger,
                rightTrigger: self.threadSafeRightTrigger,
                touchpadPosition: touchPos,
                touchpadSecondaryPosition: touchSecPos,
                isTouchpadTouching: isTouching,
                isTouchpadSecondaryTouching: isSecTouching
            )
            let updatedState = ControllerDisplayUpdatePolicy.resolve(
                current: currentState,
                sample: sample,
                deadzone: Config.displayUpdateDeadzone
            )
            self.applyDisplayState(updatedState)
        }
        timer.resume()
        displayUpdateTimer = timer
    }

    private func applyDisplayState(_ state: ControllerDisplayState) {
        leftStick = state.leftStick
        rightStick = state.rightStick
        leftTriggerValue = state.leftTriggerValue
        rightTriggerValue = state.rightTriggerValue
        displayLeftStick = state.displayLeftStick
        displayRightStick = state.displayRightStick
        displayLeftTrigger = state.displayLeftTrigger
        displayRightTrigger = state.displayRightTrigger
        displayTouchpadPosition = state.displayTouchpadPosition
        displayTouchpadSecondaryPosition = state.displayTouchpadSecondaryPosition
        displayIsTouchpadTouching = state.displayIsTouchpadTouching
        displayIsTouchpadSecondaryTouching = state.displayIsTouchpadSecondaryTouching
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

        // Update battery light bar if enabled
        updateBatteryLightBar()

        if isConnected {
            DispatchQueue.main.asyncAfter(deadline: .now() + Config.batteryUpdateInterval) { [weak self] in
                self?.updateBatteryInfo()
            }
        }
    }

    /// Updates the light bar color to reflect battery level when battery light bar mode is enabled.
    /// Red (0%) → Yellow (50%) → Green (100%). Blinks red at 5% or below.
    func updateBatteryLightBar() {
        guard threadSafeIsPlayStation,
              let currentSettings = threadSafeLEDSettings,
              currentSettings.batteryLightBar,
              currentSettings.lightBarEnabled,
              !partyModeEnabled,
              batteryLevel >= 0 else {
            stopBatteryBlink()
            return
        }

        // Start or stop blink based on battery threshold
        if batteryLevel <= Config.batteryBlinkThreshold {
            startBatteryBlink()
            return  // blink timer handles the light bar updates
        } else {
            stopBatteryBlink()
        }

        let level = Double(min(1.0, max(0.0, batteryLevel)))

        // Map battery 0-100% to hue 0°-120° (red → orange → yellow → green)
        // Using HSB gives a smooth, perceptually even gradient through all intermediate colors
        let hue = level / 3.0  // 0.0 = red (0°), 0.166 = yellow (60°), 0.333 = green (120°)
        let nsColor = NSColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0)
            .usingColorSpace(.sRGB) ?? NSColor(red: 1, green: 0, blue: 0, alpha: 1)

        var settings = currentSettings
        settings.lightBarColor = CodableColor(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent)
        )
        applyLEDSettings(settings)
    }

    private func startBatteryBlink() {
        guard batteryBlinkTimer == nil else { return }
        batteryBlinkOn = true
        batteryBlinkTimer = Timer.scheduledTimer(withTimeInterval: Config.batteryBlinkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickBatteryBlink()
            }
        }
    }

    func stopBatteryBlink() {
        batteryBlinkTimer?.invalidate()
        batteryBlinkTimer = nil
    }

    private func tickBatteryBlink() {
        guard let currentSettings = threadSafeLEDSettings,
              currentSettings.batteryLightBar,
              currentSettings.lightBarEnabled,
              !partyModeEnabled else {
            stopBatteryBlink()
            return
        }

        batteryBlinkOn.toggle()

        var settings = currentSettings
        if batteryBlinkOn {
            settings.lightBarColor = CodableColor(red: 1.0, green: 0.0, blue: 0.0)
        } else {
            settings.lightBarColor = CodableColor(red: 0.0, green: 0.0, blue: 0.0)
        }
        applyLEDSettings(settings)
    }

    // MARK: - Input Handlers

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
            storage.isDualSenseEdge = false
            storage.isDualShock = false
            storage.lock.unlock()
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)

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
            storage.isDualShock = false  // Ensure we're not flagged as DualShock
            storage.lock.unlock()
            UserDefaults.standard.set(true, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)

            setupTouchpadHandlers(
                primary: dualSenseGamepad.touchpadPrimary,
                secondary: dualSenseGamepad.touchpadSecondary,
                button: dualSenseGamepad.touchpadButton
            )

            // Set up gyroscope gesture detection
            setupMotionHandlers()

            // Set up HID monitoring for PS button, mic, and Edge paddles
            setupPlayStationHIDMonitoring()
            startKeepAliveTimer()
        }

        // DualShock 4-specific: Touchpad support (same API as DualSense)
        // Note: DualShock 4 doesn't have mic button or LED control via GameController framework
        else if let dualShockGamepad = gamepad as? GCDualShockGamepad {
            storage.lock.lock()
            storage.isDualShock = true
            storage.isDualSense = false  // Ensure we're not flagged as DualSense
            storage.isDualSenseEdge = false
            storage.lock.unlock()
            UserDefaults.standard.set(true, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)

            setupTouchpadHandlers(
                primary: dualShockGamepad.touchpadPrimary,
                secondary: dualShockGamepad.touchpadSecondary,
                button: dualShockGamepad.touchpadButton
            )

            // Set up HID monitoring for PS button
            setupPlayStationHIDMonitoring()
            startKeepAliveTimer()
        }
    }

    // MARK: - Thread-Safe Update Helpers

    nonisolated func updateLeftStick(x: Float, y: Float) {
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

    nonisolated func updateRightStick(x: Float, y: Float) {
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

    nonisolated func updateLeftTrigger(_ value: Float, pressed: Bool) {
        storage.lock.lock()
        storage.leftTrigger = value
        storage.lock.unlock()

        controllerQueue.async {
            self.handleButton(.leftTrigger, pressed: pressed)
        }
    }

    nonisolated func updateRightTrigger(_ value: Float, pressed: Bool) {
        storage.lock.lock()
        storage.rightTrigger = value
        storage.lock.unlock()

        controllerQueue.async {
            self.handleButton(.rightTrigger, pressed: pressed)
        }
    }

    nonisolated func handleButton(_ button: ControllerButton, pressed: Bool) {
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

        // Deliver chord/press callbacks FIRST, then pending releases.
        // The press callback may start a hold mapping (e.g. mouseDown for
        // mouse-click buttons). If the button was already released during
        // the chord window, the subsequent release callback will stop the
        // hold (mouseUp), completing a proper click. Reversing this order
        // causes the release to fire before any hold state exists, leaving
        // hold-path buttons (mouse clicks) permanently stuck down.
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
