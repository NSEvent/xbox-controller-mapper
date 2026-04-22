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
    var isNintendo: Bool = false   // Nintendo controller (Joy-Con, Pro Controller)
    var isJoyConLeft: Bool = false
    var isJoyConRight: Bool = false
    var isBluetoothConnection: Bool = false
    var lastInputTime: TimeInterval = 0
    var lastHIDBatteryCharging: Bool? = nil  // Track charging state changes from HID reports
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
    var motionInputEnabled: Bool = false
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

    var chargingAnimTimer: Timer?
    var chargingAnimPhase: Double = 0.0

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

    // MARK: - Controller Snapshot (single lock acquisition for hot-path polling)

    /// A value-type snapshot of controller input state, captured in a single lock acquisition.
    /// Used by JoystickHandler's 120Hz polling loop to avoid per-field lock thrashing.
    /// All ~40 bytes fit in a single cache line, eliminating repeated memory barriers.
    struct ControllerSnapshot {
        var leftStick: CGPoint = .zero
        var rightStick: CGPoint = .zero
        var leftTrigger: Float = 0
        var rightTrigger: Float = 0
        var isDualSense: Bool = false
    }

    /// Captures a consistent snapshot of all joystick-polling-relevant state in a single lock acquisition.
    /// This replaces 4-6 individual `threadSafe*` property reads that each acquire/release the lock separately.
    nonisolated func snapshot() -> ControllerSnapshot {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return ControllerSnapshot(
            leftStick: storage.leftStick,
            rightStick: storage.rightStick,
            leftTrigger: storage.leftTrigger,
            rightTrigger: storage.rightTrigger,
            isDualSense: storage.isDualSense
        )
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

    nonisolated var threadSafeIsNintendo: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isNintendo
    }

    /// Returns true if a single Joy-Con is connected (left or right, not a Pro Controller)
    nonisolated var threadSafeIsSingleJoyCon: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isJoyConLeft || storage.isJoyConRight
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

    /// Left joystick position (-1 to 1) - UI/Legacy use only.
    /// Uses CurrentValueSubject to avoid triggering objectWillChange on ControllerService,
    /// which would invalidate all 26 observing SwiftUI views on every analog input change.
    let leftStickSubject = CurrentValueSubject<CGPoint, Never>(.zero)
    var leftStick: CGPoint {
        get { leftStickSubject.value }
        set { leftStickSubject.send(newValue) }
    }

    /// Right joystick position (-1 to 1) - UI/Legacy use only
    let rightStickSubject = CurrentValueSubject<CGPoint, Never>(.zero)
    var rightStick: CGPoint {
        get { rightStickSubject.value }
        set { rightStickSubject.send(newValue) }
    }

    /// Left trigger pressure (0 to 1) - UI/Legacy use only
    let leftTriggerValueSubject = CurrentValueSubject<Float, Never>(0)
    var leftTriggerValue: Float {
        get { leftTriggerValueSubject.value }
        set { leftTriggerValueSubject.send(newValue) }
    }

    /// Right trigger pressure (0 to 1) - UI/Legacy use only
    let rightTriggerValueSubject = CurrentValueSubject<Float, Never>(0)
    var rightTriggerValue: Float {
        get { rightTriggerValueSubject.value }
        set { rightTriggerValueSubject.send(newValue) }
    }

    /// Chord detection window (accessible for testing and configuration)
    var chordWindow: TimeInterval {
        get { readStorage(\.chordWindow) }
        set { writeStorage(\.chordWindow, newValue) }
    }

    // MARK: - Throttled UI Display Values (updated at ~15Hz to avoid UI blocking)
    // These use CurrentValueSubject instead of @Published to avoid triggering
    // objectWillChange on ControllerService. Only ControllerAnalogOverlay and
    // StreamOverlayView read these — the other 24 views that observe ControllerService
    // don't need to re-render when analog values change.
    let displayLeftStickSubject = CurrentValueSubject<CGPoint, Never>(.zero)
    var displayLeftStick: CGPoint {
        get { displayLeftStickSubject.value }
        set { displayLeftStickSubject.send(newValue) }
    }
    let displayRightStickSubject = CurrentValueSubject<CGPoint, Never>(.zero)
    var displayRightStick: CGPoint {
        get { displayRightStickSubject.value }
        set { displayRightStickSubject.send(newValue) }
    }
    let displayLeftTriggerSubject = CurrentValueSubject<Float, Never>(0)
    var displayLeftTrigger: Float {
        get { displayLeftTriggerSubject.value }
        set { displayLeftTriggerSubject.send(newValue) }
    }
    let displayRightTriggerSubject = CurrentValueSubject<Float, Never>(0)
    var displayRightTrigger: Float {
        get { displayRightTriggerSubject.value }
        set { displayRightTriggerSubject.send(newValue) }
    }
    let displayTouchpadPositionSubject = CurrentValueSubject<CGPoint, Never>(.zero)
    var displayTouchpadPosition: CGPoint {
        get { displayTouchpadPositionSubject.value }
        set { displayTouchpadPositionSubject.send(newValue) }
    }
    let displayTouchpadSecondaryPositionSubject = CurrentValueSubject<CGPoint, Never>(.zero)
    var displayTouchpadSecondaryPosition: CGPoint {
        get { displayTouchpadSecondaryPositionSubject.value }
        set { displayTouchpadSecondaryPositionSubject.send(newValue) }
    }
    let displayIsTouchpadTouchingSubject = CurrentValueSubject<Bool, Never>(false)
    var displayIsTouchpadTouching: Bool {
        get { displayIsTouchpadTouchingSubject.value }
        set { displayIsTouchpadTouchingSubject.send(newValue) }
    }
    let displayIsTouchpadSecondaryTouchingSubject = CurrentValueSubject<Bool, Never>(false)
    var displayIsTouchpadSecondaryTouching: Bool {
        get { displayIsTouchpadSecondaryTouchingSubject.value }
        set { displayIsTouchpadSecondaryTouchingSubject.send(newValue) }
    }
    private var displayUpdateTimer: DispatchSourceTimer?
    private var displayTimerSuspended = false
    private var windowVisibilityObservers: [NSObjectProtocol] = []

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
    // Protected by hapticLock — accessed from both @MainActor (setup/stop) and hapticQueue (play)
    let hapticLock = NSLock()
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
            self?.controllerQueue.async { [weak self] in
                self?.handleButton(.xbox, pressed: isPressed)
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
        controllerName = controller.vendorName ?? "Game Controller"

        storage.lock.lock()
        resetTouchpadStateLocked()
        storage.lock.unlock()

        setupInputHandlers(for: controller)
        setupHaptics(for: controller)

        // Publish connection only after controller-specific handlers have populated
        // storage flags like isDualSense. MappingEngine reacts to this publisher.
        isConnected = true

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
        stopChargingAnim()
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
        storage.lastHIDBatteryCharging = nil
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
            PerformanceProbe.shared.recordDisplayTick()

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
            if updatedState == currentState {
                PerformanceProbe.shared.recordDisplayNoOpTick()
                guard !Config.performanceForceLegacyDisplayPublishing else {
                    self.applyDisplayState(updatedState)
                    return
                }
                return
            }

            self.applyDisplayState(updatedState)
        }
        timer.resume()
        displayUpdateTimer = timer
        displayTimerSuspended = false
        observeWindowVisibility()
    }

    /// Observes all app window occlusion state changes to pause/resume the display
    /// timer when no window is visible. This avoids burning CPU on @Published
    /// updates and SwiftUI invalidation when the user has minimized/hidden the app.
    private func observeWindowVisibility() {
        removeWindowVisibilityObservers()

        let checkVisibility = { [weak self] in
            guard let self = self, let timer = self.displayUpdateTimer else { return }
            let anyVisible = NSApp.windows.contains {
                $0.isVisible && $0.occlusionState.contains(.visible)
                && $0.level == .normal  // Exclude overlay panels, popovers, floating indicators
            }
            if anyVisible && self.displayTimerSuspended {
                timer.resume()
                self.displayTimerSuspended = false
            } else if !anyVisible && !self.displayTimerSuspended {
                timer.suspend()
                self.displayTimerSuspended = true
            }
        }

        let names: [Notification.Name] = [
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in checkVisibility() }
            windowVisibilityObservers.append(token)
        }
    }

    private func removeWindowVisibilityObservers() {
        for token in windowVisibilityObservers {
            NotificationCenter.default.removeObserver(token)
        }
        windowVisibilityObservers.removeAll()
    }

    private func applyDisplayState(_ state: ControllerDisplayState) {
        if Config.performanceForceLegacyDisplayPublishing {
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
            PerformanceProbe.shared.recordDisplayApply(fieldWrites: 12)
            return
        }

        var fieldWrites = 0
        if leftStick != state.leftStick {
            leftStick = state.leftStick
            fieldWrites += 1
        }
        if rightStick != state.rightStick {
            rightStick = state.rightStick
            fieldWrites += 1
        }
        if leftTriggerValue != state.leftTriggerValue {
            leftTriggerValue = state.leftTriggerValue
            fieldWrites += 1
        }
        if rightTriggerValue != state.rightTriggerValue {
            rightTriggerValue = state.rightTriggerValue
            fieldWrites += 1
        }
        if displayLeftStick != state.displayLeftStick {
            displayLeftStick = state.displayLeftStick
            fieldWrites += 1
        }
        if displayRightStick != state.displayRightStick {
            displayRightStick = state.displayRightStick
            fieldWrites += 1
        }
        if displayLeftTrigger != state.displayLeftTrigger {
            displayLeftTrigger = state.displayLeftTrigger
            fieldWrites += 1
        }
        if displayRightTrigger != state.displayRightTrigger {
            displayRightTrigger = state.displayRightTrigger
            fieldWrites += 1
        }
        if displayTouchpadPosition != state.displayTouchpadPosition {
            displayTouchpadPosition = state.displayTouchpadPosition
            fieldWrites += 1
        }
        if displayTouchpadSecondaryPosition != state.displayTouchpadSecondaryPosition {
            displayTouchpadSecondaryPosition = state.displayTouchpadSecondaryPosition
            fieldWrites += 1
        }
        if displayIsTouchpadTouching != state.displayIsTouchpadTouching {
            displayIsTouchpadTouching = state.displayIsTouchpadTouching
            fieldWrites += 1
        }
        if displayIsTouchpadSecondaryTouching != state.displayIsTouchpadSecondaryTouching {
            displayIsTouchpadSecondaryTouching = state.displayIsTouchpadSecondaryTouching
            fieldWrites += 1
        }

        if fieldWrites > 0 {
            PerformanceProbe.shared.recordDisplayApply(fieldWrites: fieldWrites)
        }
    }

    private func stopDisplayUpdateTimer() {
        removeWindowVisibilityObservers()
        // DispatchSource must not be cancelled while suspended — resume first
        if displayTimerSuspended {
            displayUpdateTimer?.resume()
            displayTimerSuspended = false
        }
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

    func updateBatteryInfo() {
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
    /// Plays a pulsing animation while charging.
    func updateBatteryLightBar() {
        guard threadSafeIsPlayStation,
              let currentSettings = threadSafeLEDSettings,
              currentSettings.batteryLightBar,
              currentSettings.lightBarEnabled,
              !partyModeEnabled,
              batteryLevel >= 0 else {
            stopBatteryBlink()
            stopChargingAnim()
            return
        }

        // Charging: pulse animation from current battery color up to green
        if batteryState == .charging {
            stopBatteryBlink()
            startChargingAnim()
            return
        } else {
            stopChargingAnim()
        }

        // Low battery: blink red
        if batteryLevel <= Config.batteryBlinkThreshold {
            startBatteryBlink()
            return
        } else {
            stopBatteryBlink()
        }

        applyBatteryColor()
    }

    /// Applies the static battery-level color (no animation).
    private func applyBatteryColor() {
        guard let currentSettings = threadSafeLEDSettings else { return }

        let level = Double(min(1.0, max(0.0, batteryLevel)))

        // Map battery 0-100% to hue 0°-120° (red → orange → yellow → green)
        let hue = level / 3.0
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

    /// Returns the battery-level hue (0°-120°) as an RGB CodableColor.
    private func batteryHueColor() -> (red: Double, green: Double, blue: Double) {
        let level = Double(min(1.0, max(0.0, batteryLevel)))
        let hue = level / 3.0
        let nsColor = NSColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 1.0)
            .usingColorSpace(.sRGB) ?? NSColor(red: 1, green: 0, blue: 0, alpha: 1)
        return (Double(nsColor.redComponent), Double(nsColor.greenComponent), Double(nsColor.blueComponent))
    }

    // MARK: - Low Battery Blink

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

    // MARK: - Charging Animation

    /// Pulsing animation while charging: smoothly breathes from the current battery color
    /// up to bright green and back, like energy flowing in.
    private func startChargingAnim() {
        guard chargingAnimTimer == nil else { return }
        chargingAnimPhase = 0.0
        let interval = 1.0 / Config.chargingAnimFrequency
        chargingAnimTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickChargingAnim()
            }
        }
    }

    func stopChargingAnim() {
        chargingAnimTimer?.invalidate()
        chargingAnimTimer = nil
    }

    private func tickChargingAnim() {
        guard let currentSettings = threadSafeLEDSettings,
              currentSettings.batteryLightBar,
              currentSettings.lightBarEnabled,
              !partyModeEnabled,
              batteryState == .charging else {
            stopChargingAnim()
            return
        }

        // Advance phase (0-1 over one cycle)
        let phaseStep = 1.0 / (Config.chargingAnimFrequency * Config.chargingAnimCycleDuration)
        chargingAnimPhase += phaseStep
        if chargingAnimPhase >= 1.0 { chargingAnimPhase -= 1.0 }

        // Smooth sine pulse: 0 → 1 → 0
        let pulse = (1.0 - cos(chargingAnimPhase * 2.0 * .pi)) / 2.0

        // Blend from battery-level color (base) toward bright green (target)
        let base = batteryHueColor()
        let targetGreen = (red: 0.0, green: 1.0, blue: 0.0)

        let r = base.red + (targetGreen.red - base.red) * pulse
        let g = base.green + (targetGreen.green - base.green) * pulse
        let b = base.blue + (targetGreen.blue - base.blue) * pulse

        var settings = currentSettings
        settings.lightBarColor = CodableColor(red: r, green: g, blue: b)
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
        // Log controller info for diagnostics (visible in Console.app)
        NSLog("[ControllerKeys] vendorName=%@  productCategory=%@  extendedGamepad=%@  microGamepad=%@",
              controller.vendorName ?? "(nil)",
              controller.productCategory,
              controller.extendedGamepad != nil ? "YES" : "NO",
              controller.microGamepad != nil ? "YES" : "NO")

        // Detect Nintendo controller type before the extendedGamepad guard,
        // since single Joy-Cons only provide physicalInputProfile.
        detectNintendoController(controller)

        // Try extendedGamepad first (works for Xbox, DualSense, Pro Controller, paired Joy-Cons)
        guard let gamepad = controller.extendedGamepad else {
            // Single Joy-Cons don't expose extendedGamepad or microGamepad — they only
            // provide physicalInputProfile. Use it to dynamically bind available elements.
            NSLog("[ControllerKeys] No extendedGamepad — using physicalInputProfile fallback")
            setupPhysicalInputProfileHandlers(controller.physicalInputProfile)
            return
        }

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

        // Log available elements for diagnostics (helps debug Joy-Con/third-party controllers)
        if storage.lock.withLock({ storage.isNintendo }) {
            NSLog("[ControllerKeys] extendedGamepad elements: A=%d B=%d X=%d Y=%d LS=%d RS=%d LT=%d RT=%d dpad=%d menu=%d options=%d home=%d L3=%d R3=%d leftStick=%d rightStick=%d",
                  gamepad.buttonA != nil ? 1 : 0, gamepad.buttonB != nil ? 1 : 0,
                  gamepad.buttonX != nil ? 1 : 0, gamepad.buttonY != nil ? 1 : 0,
                  gamepad.leftShoulder != nil ? 1 : 0, gamepad.rightShoulder != nil ? 1 : 0,
                  gamepad.leftTrigger != nil ? 1 : 0, gamepad.rightTrigger != nil ? 1 : 0,
                  gamepad.dpad != nil ? 1 : 0, gamepad.buttonMenu != nil ? 1 : 0,
                  gamepad.buttonOptions != nil ? 1 : 0, gamepad.buttonHome != nil ? 1 : 0,
                  gamepad.leftThumbstickButton != nil ? 1 : 0, gamepad.rightThumbstickButton != nil ? 1 : 0,
                  gamepad.leftThumbstick != nil ? 1 : 0, gamepad.rightThumbstick != nil ? 1 : 0)
        }

        if let xboxGamepad = gamepad as? GCXboxGamepad {
            storage.lock.lock()
            storage.isDualSense = false
            storage.isDualSenseEdge = false
            storage.isDualShock = false
            storage.isNintendo = false
            storage.isJoyConLeft = false
            storage.isJoyConRight = false
            storage.lock.unlock()
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)

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
            storage.isDualShock = false
            storage.isNintendo = false
            storage.isJoyConLeft = false
            storage.isJoyConRight = false
            storage.lock.unlock()
            UserDefaults.standard.set(true, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)

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
            storage.isDualSense = false
            storage.isDualSenseEdge = false
            storage.isNintendo = false
            storage.isJoyConLeft = false
            storage.isJoyConRight = false
            storage.lock.unlock()
            UserDefaults.standard.set(true, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)

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

    // MARK: - Nintendo Controller Detection

    /// Detects Nintendo controllers (Joy-Con, Pro Controller) via vendor name and product category.
    /// Must be called before the extendedGamepad guard since single Joy-Cons only provide physicalInputProfile.
    ///
    /// Known productCategory values from GameController framework:
    ///   "Nintendo Switch Joy-Con (L)", "Nintendo Switch Joy-Con (R)",
    ///   "Nintendo Switch Joy-Con (L/R)", "Switch Pro Controller"
    /// vendorName is the Bluetooth device name: "Joy-Con (L)", "Joy-Con (R)", "Pro Controller"
    private func detectNintendoController(_ controller: GCController) {
        let vendorName = controller.vendorName?.lowercased() ?? ""
        let productCategory = controller.productCategory.lowercased()

        // Check both vendorName and productCategory for Nintendo identifiers
        let isNintendoController = vendorName.contains("joy-con") || vendorName.contains("pro controller")
            || productCategory.contains("joy-con") || productCategory.contains("joycon")
            || productCategory.contains("pro controller")
            || productCategory.contains("nintendo")

        guard isNintendoController else { return }

        NSLog("[ControllerKeys] Nintendo detected — vendorName=%@  productCategory=%@",
              controller.vendorName ?? "(nil)", controller.productCategory)

        // Check both vendorName and productCategory for L/R — vendorName is "Joy-Con (L)",
        // productCategory is "Nintendo Switch Joy-Con (L)". Check both for robustness.
        let combined = vendorName + " " + productCategory
        let isLeft = combined.contains("(l)") && !combined.contains("(l/r)")
        let isRight = combined.contains("(r)") && !combined.contains("(l/r)")
        NSLog("[ControllerKeys] Joy-Con L/R detection: isLeft=%d  isRight=%d", isLeft ? 1 : 0, isRight ? 1 : 0)

        storage.lock.lock()
        storage.isNintendo = true
        storage.isJoyConLeft = isLeft
        storage.isJoyConRight = isRight
        storage.isDualSense = false
        storage.isDualSenseEdge = false
        storage.isDualShock = false
        storage.lock.unlock()

        UserDefaults.standard.set(true, forKey: Config.lastControllerWasNintendoKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
    }

    // MARK: - PhysicalInputProfile Handlers (Single Joy-Con, etc.)

    /// Sets up input handlers by dynamically enumerating the controller's physicalInputProfile.
    /// Single Joy-Cons don't expose extendedGamepad or microGamepad — they only provide
    /// physicalInputProfile with a dynamic set of buttons, axes, and dpads.
    private func setupPhysicalInputProfileHandlers(_ profile: GCPhysicalInputProfile) {
        // Map known GCInput element names to ControllerButton cases
        let buttonMap: [(String, ControllerButton)] = [
            (GCInputButtonA, .a),
            (GCInputButtonB, .b),
            (GCInputButtonX, .x),
            (GCInputButtonY, .y),
            (GCInputLeftShoulder, .leftBumper),
            (GCInputRightShoulder, .rightBumper),
            (GCInputLeftTrigger, .leftTrigger),
            (GCInputRightTrigger, .rightTrigger),
            (GCInputButtonMenu, .menu),
            (GCInputButtonOptions, .view),
            (GCInputButtonHome, .xbox),
            (GCInputLeftThumbstickButton, .leftThumbstick),
            (GCInputRightThumbstickButton, .rightThumbstick),
        ]

        var boundCount = 0
        for (inputName, controllerButton) in buttonMap {
            if let element = profile.buttons[inputName] {
                bindButton(element, to: controllerButton)
                boundCount += 1
            }
        }

        // D-pad
        if let dpad = profile.dpads[GCInputDirectionPad] {
            bindButton(dpad.up, to: .dpadUp)
            bindButton(dpad.down, to: .dpadDown)
            bindButton(dpad.left, to: .dpadLeft)
            bindButton(dpad.right, to: .dpadRight)
            boundCount += 4
        }

        // Left thumbstick (analog) — use for mouse movement
        if let leftStick = profile.dpads[GCInputLeftThumbstick] {
            leftStick.valueChangedHandler = { [weak self] _, xValue, yValue in
                self?.updateLeftStick(x: xValue, y: yValue)
            }
        } else if let dpad = profile.dpads[GCInputDirectionPad] {
            // Fallback: Joy-Con stick may be exposed as a D-pad rather than a thumbstick.
            // Use it for mouse movement so the user gets analog-like cursor control.
            dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
                self?.updateLeftStick(x: xValue, y: yValue)
            }
        }

        // Right thumbstick (analog)
        if let rightStick = profile.dpads[GCInputRightThumbstick] {
            rightStick.valueChangedHandler = { [weak self] _, xValue, yValue in
                self?.updateRightStick(x: xValue, y: yValue)
            }
        }

        // Log all available elements for diagnostics
        NSLog("[ControllerKeys] physicalInputProfile: bound %d elements. buttons=%@ dpads=%@ axes=%@",
              boundCount,
              profile.buttons.keys.sorted().joined(separator: ", "),
              profile.dpads.keys.sorted().joined(separator: ", "),
              profile.axes.keys.sorted().joined(separator: ", "))
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

        controllerQueue.async { [weak self] in
            self?.handleButton(.leftTrigger, pressed: pressed)
        }
    }

    nonisolated func updateRightTrigger(_ value: Float, pressed: Bool) {
        storage.lock.lock()
        storage.rightTrigger = value
        storage.lock.unlock()

        controllerQueue.async { [weak self] in
            self?.handleButton(.rightTrigger, pressed: pressed)
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
