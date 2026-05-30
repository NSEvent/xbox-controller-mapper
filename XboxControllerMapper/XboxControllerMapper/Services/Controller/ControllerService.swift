import Foundation
import AppKit
import GameController
import Combine
import CoreHaptics
import IOKit
import IOKit.hid
import SwiftUI
import CoreAudio
import AudioToolbox
import AVFoundation

struct ControllerButtonEvent: Equatable {
	let button: ControllerButton
	let pressed: Bool
}

private enum RawGuideEventSource: String {
	case guideMonitor = "guide monitor"
	case eliteHelper = "elite helper"
}

// MARK: - Thread-Safe Input State (High Performance)

final class ControllerStorage: @unchecked Sendable {
    /// Matches other nonisolated state holders retained by MainActor services.
    /// Without this, test teardown can hit Swift's isolated deinit hop and abort
    /// in libmalloc when nested detector state is released.
    nonisolated deinit { }

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
    var touchpadLastUpdate: TimeInterval = 0
    var touchpadSecondaryLastUpdate: TimeInterval = 0
    var touchpadSecondaryLastTouchTime: TimeInterval = 0
    var isDualSense: Bool = false
    var isDualSenseEdge: Bool = false
    var isDualShock: Bool = false  // PS4 DualShock 4 controller
    var isNintendo: Bool = false   // Nintendo controller (Joy-Con, Pro Controller)
    var isXboxElite: Bool = false  // Xbox Elite Series 2 controller
    var isSteamController: Bool = false
    var isAppleTVRemote: Bool = false
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

    // Steam Controller touchpad display + quadrant-click tracking. Kept
    // separate from DualSense secondary-touch state so the left Steam pad
    // never trips two-finger gesture suppression on the right pad cursor path.
    var steamLeftTouchpadPosition: CGPoint = .zero
    var steamRightTouchpadPosition: CGPoint = .zero
    var isSteamLeftTouchpadTouching: Bool = false
    var isSteamRightTouchpadTouching: Bool = false
	var steamLeftTouchpadClickArmed: Bool = false
	var steamLeftTouchpadClickStartPosition: CGPoint = .zero
    var activeSteamLeftTouchpadClickQuadrant: ControllerButton?
    var activeSteamRightTouchpadClickQuadrant: ControllerButton?
    var steamTwoPadGestureActiveUntil: TimeInterval = 0
    var steamTwoPadGestureWasActive: Bool = false

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

	    // Nintendo Pro Controller HID button state
	    var lastNintendoHomeState: Bool = false
	    var appleTVRemoteTouchReleaseWorkItem: DispatchWorkItem?
    var appleTVRemoteActiveSystemKeyTypes: Set<Int> = []
    var appleTVRemoteSystemKeyTypeSuppressUntil: [Int: TimeInterval] = [:]
    var appleTVRemoteActiveButtonUsages: [ControllerButton: Set<UInt64>] = [:]
    var appleTVRemoteButtonReleaseWorkItems: [ControllerButton: DispatchWorkItem] = [:]
    var appleTVRemoteCircularScrollActive: Bool = false

    // DualSense Edge button state (paddles and function buttons)
    var lastLeftPaddleState: Bool = false
    var lastRightPaddleState: Bool = false
    var lastLeftFunctionState: Bool = false
    var lastRightFunctionState: Bool = false

	// Elite raw HID paddle producers are centrally deduped here because helper and guide monitor
	// visibility differs by Elite 2 firmware/connection mode.
	var elitePaddleEventSource: ElitePaddleEventSource = .none
	var eliteRawPaddleState: [Int: Bool] = [:]
	var rawHIDGuidePressed = false
	var rawHIDGuideLastEventTime: TimeInterval?

    // Chord Detection State
    var pendingButtons: Set<ControllerButton> = []
    var capturedButtonsInWindow: Set<ControllerButton> = []
    var pendingReleases: [ControllerButton: TimeInterval] = [:]
    var chordWorkItem: DispatchWorkItem?
    var chordWindow: TimeInterval = 0.15
    var chordParticipantButtons: Set<ControllerButton> = []
    var lowLatencyInputEnabled: Bool = false

    // Callbacks
    var onButtonPressed: ((ControllerButton) -> Void)?
    var onButtonReleased: ((ControllerButton, TimeInterval) -> Void)?
    var onChordDetected: ((Set<ControllerButton>) -> Void)?
    var onLeftStickMoved: ((CGPoint) -> Void)?
    var onRightStickMoved: ((CGPoint) -> Void)?
    var onTouchpadMoved: ((CGPoint) -> Void)?  // Delta movement
    var onSteamLeftTouchpadMoved: ((CGPoint) -> Void)?  // Left-pad delta movement for app-owned scroll
    var onAppleTVRemoteCircularScroll: ((CGFloat) -> Void)?
    var onTouchpadGesture: ((TouchpadGesture) -> Void)?
    var onTouchpadTap: (() -> Void)?  // Single tap (touch + release without moving)
    var onControllerButtonTap: ((ControllerButton) -> Void)?  // One-shot virtual tap events
    var onTouchpadTwoFingerTap: (() -> Void)?  // Two-finger tap or click (right-click)
    var onTouchpadLongTap: (() -> Void)?  // Long tap (touch held without moving)
    var onTouchpadTwoFingerLongTap: (() -> Void)?  // Two-finger long tap
    var onTouchpadRegionTap: ((TouchpadRegion) -> Void)?  // Region-specific tap
    /// When true, region-click events only fire while a finger is currently touching
    /// the pad. Default true. Mirrors `JoystickSettings.requireActiveTouchForRegionClick`
    /// and is updated by MappingEngine whenever joystick settings change.
    var requireActiveTouchForRegionClick: Bool = true

    /// Mirrors `Profile.touchpadInputMode`. Read by the touchpad input pipeline
    /// to decide which button events to fire (whole-pad or quadrant variants).
    /// Updated by MappingEngine on profile change.
    var touchpadInputMode: TouchpadInputMode = .wholePad

    /// Tracks which quadrant the touchpad's physical click is currently in,
    /// across press → release. Cleared on release. Used to ensure the same
    /// quadrant button gets both press AND release events even if the user's
    /// finger drifts to a different quadrant during the hold.
    var activeTouchpadClickQuadrant: ControllerButton?
    var touchpadLongTapTimer: DispatchWorkItem?  // Timer for long tap detection
    var touchpadLongTapFired: Bool = false  // Whether long tap already triggered for this touch

    // Motion Gesture State (supported controller gyroscope)
    var motionInputEnabled: Bool = false
    var motionGestureDetector = MotionGestureDetector()
    var onMotionGesture: ((MotionGestureType) -> Void)?

    // Gyro aiming: accumulated rotation rates between polls (averaged on consume)
    // DS4 raw-HID gyro bias calibration. Apple's framework calibrates DualSense
    // automatically; for DS4 we sample the average gyro reading at rest so we
    // can subtract it (otherwise the hardware drift makes one tilt direction
    // feel stronger than the other).
    var ds4GyroPitchBiasSum: Double = 0
    var ds4GyroRollBiasSum: Double = 0
    var ds4GyroBiasSampleCount: Int = 0
    var ds4GyroPitchBias: Double = 0
    var ds4GyroRollBias: Double = 0
    var steamGyroPitchBiasSum: Double = 0
    var steamGyroRollBiasSum: Double = 0
    var steamGyroBiasSampleCount: Int = 0
    var steamGyroPitchBias: Double = 0
    var steamGyroRollBias: Double = 0
    var motionPitchAccum: Double = 0
    var motionRollAccum: Double = 0
    var motionSampleCount: Int = 0
}

/// Service for managing game controller connection and input
@MainActor
class ControllerService: ObservableObject {
	private static let rawGuideStalePressRecoveryInterval: TimeInterval = 2.0

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @Published var isConnected = false
    @Published var connectedController: GCController?
    @Published var currentControllerIdentity: ControllerIdentity?
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

    /// Monotonically increasing generation counter for the current connection.
    /// Incremented each time `controllerConnected(_:)` runs. Used in diagnostic
    /// logs to correlate connect/disconnect events during Bluetooth reconnection.
    private var connectionGeneration: UInt64 = 0

    // HID monitoring for DualSense mic button (not exposed by GameController framework)
    var hidManager: IOHIDManager?
    var hidDevice: IOHIDDevice?
    var psHIDRegistrations: [PlayStationHIDRegistration] = []
    var bluetoothOutputSeq: UInt8 = 0  // Sequence number for Bluetooth output reports (0-15)
    var keepAliveTimer: DispatchSourceTimer?

    // Generic HID controller fallback (for controllers not recognized by GameController framework)
    var genericHIDManager: IOHIDManager?
    var genericHIDController: GenericHIDController?
    var genericHIDFallbackTimer: DispatchWorkItem?
    @Published var isGenericController = false

    /// Retained context pointer for generic HID callbacks — released in cleanupGenericHIDMonitoring().
    var genericHIDCallbackContext: UnsafeMutableRawPointer?

    // Steam Controller 2026 / Triton raw HID monitoring (works without Steam running)
    var steamHIDManager: IOHIDManager?
    var steamHIDControllers: [SteamControllerHIDController] = []
    var steamHIDActiveDevice: IOHIDDevice?
    var steamHIDCallbackContext: UnsafeMutableRawPointer?
    let steamHIDControllerLock = NSLock()
    var activeSteamHIDController: SteamControllerHIDController?

    // Nintendo Pro Controller HID monitoring (Home button not exposed by GameController framework)
    var nintendoHIDManager: IOHIDManager?
    var nintendoHIDDevice: IOHIDDevice?
    var nintendoHIDReportBuffer: UnsafeMutablePointer<UInt8>?
    var nintendoHIDCallbackContext: UnsafeMutableRawPointer?

	// Apple TV/Siri Remote HID monitoring (buttons + touch surface)
	var appleTVRemoteHIDManager: IOHIDManager?
	var appleTVRemoteHIDButtonManager: IOHIDManager?
	var appleTVRemoteHIDDevice: IOHIDDevice?
	var appleTVRemoteHIDTouchDevice: IOHIDDevice?
	var appleTVRemoteHIDTouchReportBuffer: UnsafeMutablePointer<UInt8>?
	var appleTVRemoteHIDTouchReportBufferSize: Int = 0
	var appleTVRemoteHIDCallbackContext: UnsafeMutableRawPointer?
	var appleTVRemoteMultitouchStarted: Bool = false
	var appleTVRemoteHIDButtonManagerOpenOptions = IOOptionBits(kIOHIDOptionsTypeNone)
	var appleTVRemoteSystemEventTap: CFMachPort?
	var appleTVRemoteSystemEventRunLoopSource: CFRunLoopSource?
	var appleTVRemoteSystemEventTapContext: UnsafeMutableRawPointer?

    /// Xbox Elite Series 2 helper process (separate binary without GameController.framework)
    var eliteHelperProcess: Process?
	var eliteHelperHandlesPaddles: Bool?

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
        var touchpadPosition: CGPoint = .zero
        var isTouchpadTouching: Bool = false
        /// True for any controller with gyroscope sensors (DualSense, DS4, Steam Controller).
        var hasMotion: Bool = false
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
            touchpadPosition: storage.touchpadPosition,
            isTouchpadTouching: storage.isTouchpadTouching,
            hasMotion: storage.isDualSense || storage.isDualShock || storage.isSteamController
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
        let secondaryFresh = (now - storage.touchpadSecondaryLastTouchTime) < Config.touchpadSecondaryStaleInterval
        let blocked = storage.touchpadMovementBlocked ||
            (!storage.isSteamController && secondaryFresh)
        storage.lock.unlock()
        return blocked
    }

    nonisolated var threadSafeIsDualSense: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return !storage.isSteamController && storage.isDualSense
    }

    nonisolated var threadSafeIsDualSenseEdge: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return !storage.isSteamController && storage.isDualSenseEdge
    }

    nonisolated var threadSafeIsDualShock: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return !storage.isSteamController && storage.isDualShock
    }

    /// Returns true if connected controller is any PlayStation controller (DualSense, DualShock)
    nonisolated var threadSafeIsPlayStation: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return !storage.isSteamController && (storage.isDualSense || storage.isDualShock)
    }

    nonisolated var threadSafeHasMotion: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isDualSense || storage.isDualShock || storage.isSteamController
    }

    nonisolated var threadSafeIsNintendo: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isNintendo
    }

    nonisolated var threadSafeIsXboxElite: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return !storage.isSteamController && storage.isXboxElite
    }

    nonisolated var threadSafeIsSteamController: Bool {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.isSteamController
    }

    nonisolated var threadSafeIsAppleTVRemote: Bool {
		storage.lock.lock()
		defer { storage.lock.unlock() }
		return storage.isAppleTVRemote
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

    var chordParticipantButtons: Set<ControllerButton> {
        get { readStorage(\.chordParticipantButtons) }
        set { writeStorage(\.chordParticipantButtons, newValue) }
    }

    var lowLatencyInputEnabled: Bool {
        get { readStorage(\.lowLatencyInputEnabled) }
        set { writeStorage(\.lowLatencyInputEnabled, newValue) }
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
    let displaySteamLeftTouchpadPositionSubject = CurrentValueSubject<CGPoint, Never>(.zero)
    var displaySteamLeftTouchpadPosition: CGPoint {
        get { displaySteamLeftTouchpadPositionSubject.value }
        set { displaySteamLeftTouchpadPositionSubject.send(newValue) }
    }
    let displaySteamRightTouchpadPositionSubject = CurrentValueSubject<CGPoint, Never>(.zero)
    var displaySteamRightTouchpadPosition: CGPoint {
        get { displaySteamRightTouchpadPositionSubject.value }
        set { displaySteamRightTouchpadPositionSubject.send(newValue) }
    }
    let displayIsSteamLeftTouchpadTouchingSubject = CurrentValueSubject<Bool, Never>(false)
    var displayIsSteamLeftTouchpadTouching: Bool {
        get { displayIsSteamLeftTouchpadTouchingSubject.value }
        set { displayIsSteamLeftTouchpadTouchingSubject.send(newValue) }
    }
    let displayIsSteamRightTouchpadTouchingSubject = CurrentValueSubject<Bool, Never>(false)
    var displayIsSteamRightTouchpadTouching: Bool {
        get { displayIsSteamRightTouchpadTouchingSubject.value }
        set { displayIsSteamRightTouchpadTouchingSubject.send(newValue) }
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
    var onSteamLeftTouchpadMoved: ((CGPoint) -> Void)? {
        get { readStorage(\.onSteamLeftTouchpadMoved) }
        set { writeStorage(\.onSteamLeftTouchpadMoved, newValue) }
    }
    var onAppleTVRemoteCircularScroll: ((CGFloat) -> Void)? {
		get { readStorage(\.onAppleTVRemoteCircularScroll) }
		set { writeStorage(\.onAppleTVRemoteCircularScroll, newValue) }
    }
    var onTouchpadGesture: ((TouchpadGesture) -> Void)? {
        get { readStorage(\.onTouchpadGesture) }
        set { writeStorage(\.onTouchpadGesture, newValue) }
    }
    var onTouchpadTap: (() -> Void)? {
        get { readStorage(\.onTouchpadTap) }
        set { writeStorage(\.onTouchpadTap, newValue) }
    }
    var onControllerButtonTap: ((ControllerButton) -> Void)? {
        get { readStorage(\.onControllerButtonTap) }
        set { writeStorage(\.onControllerButtonTap, newValue) }
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
    var onTouchpadRegionTap: ((TouchpadRegion) -> Void)? {
        get { readStorage(\.onTouchpadRegionTap) }
        set { writeStorage(\.onTouchpadRegionTap, newValue) }
    }
    var requireActiveTouchForRegionClick: Bool {
        get { readStorage(\.requireActiveTouchForRegionClick) }
        set { writeStorage(\.requireActiveTouchForRegionClick, newValue) }
    }
    var touchpadInputMode: TouchpadInputMode {
        get { readStorage(\.touchpadInputMode) }
        set { writeStorage(\.touchpadInputMode, newValue) }
    }
    var onMotionGesture: ((MotionGestureType) -> Void)? {
        get { readStorage(\.onMotionGesture) }
        set { writeStorage(\.onMotionGesture, newValue) }
    }

    private var cancellables = Set<AnyCancellable>()

    // Low-level monitor for Xbox Guide button
	private let guideMonitor: XboxGuideMonitor

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
		self.guideMonitor = XboxGuideMonitor(enableHardwareMonitoring: shouldEnableHardwareMonitoring)

        // Load last controller type (so UI shows correct button labels when no controller is connected)
        storage.isDualSense = UserDefaults.standard.bool(forKey: Config.lastControllerWasDualSenseKey)
        storage.isDualSenseEdge = UserDefaults.standard.bool(forKey: Config.lastControllerWasDualSenseEdgeKey)
        storage.isDualShock = UserDefaults.standard.bool(forKey: Config.lastControllerWasDualShockKey)
        storage.isXboxElite = UserDefaults.standard.bool(forKey: Config.lastControllerWasXboxEliteKey)
        storage.isSteamController = UserDefaults.standard.bool(forKey: Config.lastControllerWasSteamControllerKey)
		storage.isAppleTVRemote = UserDefaults.standard.bool(forKey: Config.lastControllerWasAppleTVRemoteKey)
        if storage.isSteamController {
            storage.isDualSense = false
            storage.isDualSenseEdge = false
            storage.isDualShock = false
            storage.isXboxElite = false
			storage.isAppleTVRemote = false
		} else if storage.isAppleTVRemote {
			storage.isDualSense = false
			storage.isDualSenseEdge = false
			storage.isDualShock = false
			storage.isXboxElite = false
			storage.isNintendo = false
        }

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

			setupSteamControllerHIDMonitoring()
			setupGenericHIDMonitoring()
			setupAppleTVRemoteHIDMonitoring()
		}

        guideMonitor.onGuideButtonAction = { [weak self] isPressed in
			guard let self else { return }
			let events = self.guideMonitorGuideButtonEvents(pressed: isPressed)
			guard !events.isEmpty else { return }
			self.controllerQueue.async { [weak self] in
				for event in events {
					self?.handleButton(event.button, pressed: event.pressed)
				}
			}
        }

        guideMonitor.onPaddleAction = { [weak self] paddleIndex, isPressed in
			guard let button = self?.guideMonitorPaddleButton(for: paddleIndex, pressed: isPressed) else { return }
            self?.controllerQueue.async { [weak self] in
                self?.handleButton(button, pressed: isPressed)
            }
        }
    }

	func cleanup() {
		guideMonitor.stop()
		stopDiscovery()
		batteryMonitor.stopMonitoring()
		cleanupSteamControllerHIDMonitoring()
		cleanupGenericHIDMonitoring()
		cleanupAppleTVRemoteHIDMonitoring()
		stopEliteHelper()
		resetRawHIDGuideButtonState()
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
                guard let self = self else { return }
                if let controller = notification.object as? GCController,
                   controller == self.connectedController {
                    // Guard against late/out-of-order disconnect notifications.
                    // During Bluetooth reconnect macOS may reuse the same GCController
                    // object and deliver didDisconnect AFTER didConnect. Check the
                    // system controller list to verify the controller is actually gone.
                    if GCController.controllers().contains(controller) {
                        NSLog("[ControllerKeys] Ignoring stale disconnect (gen=%llu) — controller still in system list",
                              self.connectionGeneration)
                        return
                    }
                    NSLog("[ControllerKeys] controllerDisconnected — generation=%llu", self.connectionGeneration)
                    self.controllerDisconnected()
                }
            }
            .store(in: &cancellables)

		NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
			.receive(on: DispatchQueue.main)
			.sink { [weak self] _ in
				self?.scheduleAppleTVRemoteWakeRefresh()
			}
			.store(in: &cancellables)
    }

	private func scheduleAppleTVRemoteWakeRefresh() {
		let shouldRefresh = storage.lock.withLock {
			storage.isAppleTVRemote
		} || appleTVRemoteHIDManager != nil
			|| appleTVRemoteHIDButtonManager != nil
			|| appleTVRemoteMultitouchStarted
			|| CKAppleTVRemoteMultitouchIsRunning()

		guard shouldRefresh else { return }

		reenableAppleTVRemoteSystemEventSuppressionIfNeeded()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
			self?.refreshAppleTVRemoteHIDMonitoringAfterWake()
		}
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
        if steamHIDActiveDevice != nil {
            NSLog("[ControllerKeys] Ignoring GameController connection while Steam Controller raw HID is active")
            return
        }
        if Self.isSteamControllerMetadata(
            vendorName: controller.vendorName,
            productCategory: controller.productCategory
        ) {
            NSLog("[ControllerKeys] Ignoring Steam Controller GameController route; raw HID owns Steam input")
            return
        }

        connectionGeneration += 1
        NSLog("[ControllerKeys] controllerConnected — generation=%llu vendor=%@",
              connectionGeneration, controller.vendorName ?? "(nil)")

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
        currentControllerIdentity = nil

        storage.lock.lock()
        resetTouchpadStateLocked()
        storage.lock.unlock()

        setupInputHandlers(for: controller)
        setupHaptics(for: controller)
        if currentControllerIdentity == nil {
            currentControllerIdentity = ControllerIdentityResolver.identity(
                for: controller,
                preferredDevice: hidDevice
            )
        }

        // Publish connection only after controller-specific handlers have populated
        // storage flags like isDualSense/isXboxElite. MappingEngine reacts to this publisher.
        isConnected = true

        // Force SwiftUI to re-read computed properties (threadSafeIsXboxElite, etc.)
        // that depend on storage flags set during setupInputHandlers.
        // Deferred to next run loop to ensure SwiftUI processes this as a separate update cycle.
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.playHaptic(intensity: 0.7, sharpness: 0.6, duration: 0.12)
        }
        updateBatteryInfo()
        startDisplayUpdateTimer()
    }

    func controllerDisconnected() {
		let wasAppleTVRemote = storage.lock.withLock { storage.isAppleTVRemote }
		if wasAppleTVRemote {
			releaseAppleTVRemoteButtonsIfNeeded()
			releaseAppleTVRemoteTouchIfStillActive()
		}

        // Disable motion sensors before disconnecting
        connectedController?.motion?.sensorsActive = false
        connectedController = nil
        isConnected = false
        currentControllerIdentity = nil
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
        cleanupNintendoHIDMonitoring()  // Clean up Nintendo Home button monitoring
		if !wasAppleTVRemote {
			cleanupAppleTVRemoteHIDMonitoring()  // Clean up Apple TV Remote HID monitoring
		}
        stopEliteHelper()  // Clean up Elite helper process

        storage.lock.lock()
        storage.activeButtons.removeAll()
        storage.buttonPressTimestamps.removeAll()
        storage.pendingButtons.removeAll()
        storage.capturedButtonsInWindow.removeAll()
        storage.pendingReleases.removeAll()
        storage.chordWorkItem?.cancel()
        storage.leftStick = .zero
        storage.rightStick = .zero
        storage.leftTrigger = 0
        storage.rightTrigger = 0
        storage.lastInputTime = 0
        // Reset touchpad state (but keep isDualSense to remember last controller type)
        resetTouchpadStateLocked()
        resetMotionStateLocked()
        storage.lastMicButtonState = false
        storage.lastPSButtonState = false
        storage.lastNintendoHomeState = false
        storage.lastHIDBatteryCharging = nil
        // Reset DualSense Edge paddle/function button state
        storage.lastLeftPaddleState = false
        storage.lastRightPaddleState = false
        storage.lastLeftFunctionState = false
		storage.lastRightFunctionState = false
		storage.elitePaddleEventSource = .none
		storage.eliteRawPaddleState.removeAll()
		storage.rawHIDGuidePressed = false
		storage.rawHIDGuideLastEventTime = nil
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
        storage.touchpadLastUpdate = 0
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
        storage.steamLeftTouchpadPosition = .zero
        storage.steamRightTouchpadPosition = .zero
        storage.isSteamLeftTouchpadTouching = false
        storage.isSteamRightTouchpadTouching = false
		storage.steamLeftTouchpadClickArmed = false
		storage.steamLeftTouchpadClickStartPosition = .zero
        storage.activeSteamLeftTouchpadClickQuadrant = nil
        storage.activeSteamRightTouchpadClickQuadrant = nil
        storage.steamTwoPadGestureActiveUntil = 0
		storage.steamTwoPadGestureWasActive = false
    }

	nonisolated func guideMonitorPaddleButton(for paddleIndex: Int, pressed: Bool) -> ControllerButton? {
		eliteRawHIDPaddleButton(for: paddleIndex, pressed: pressed)
	}

	nonisolated func eliteHelperPaddleButton(for paddleIndex: Int, pressed: Bool) -> ControllerButton? {
		eliteRawHIDPaddleButton(for: paddleIndex, pressed: pressed)
	}

	nonisolated func guideMonitorGuideButtonEvents(
		pressed: Bool,
		now: TimeInterval = CFAbsoluteTimeGetCurrent()
	) -> [ControllerButtonEvent] {
		rawHIDGuideButtonEvents(source: .guideMonitor, pressed: pressed, now: now)
	}

	nonisolated func eliteHelperGuideButtonEvents(
		pressed: Bool,
		now: TimeInterval = CFAbsoluteTimeGetCurrent()
	) -> [ControllerButtonEvent] {
		rawHIDGuideButtonEvents(source: .eliteHelper, pressed: pressed, now: now)
	}

	private nonisolated func eliteRawHIDPaddleButton(for paddleIndex: Int, pressed: Bool) -> ControllerButton? {
		guard let button = Self.xboxElitePaddleButton(for: paddleIndex) else { return nil }
		storage.lock.lock()
		defer { storage.lock.unlock() }
		guard storage.elitePaddleEventSource == .rawHID else { return nil }
		if storage.eliteRawPaddleState[paddleIndex] == pressed {
			return nil
		}
		storage.eliteRawPaddleState[paddleIndex] = pressed
		return button
	}

	private nonisolated func rawHIDGuideButtonEvents(
		source: RawGuideEventSource,
		pressed: Bool,
		now: TimeInterval
	) -> [ControllerButtonEvent] {
		let result: (events: [ControllerButtonEvent], logMessage: String?)

		storage.lock.lock()
		if storage.rawHIDGuidePressed == pressed {
			let eventGap = storage.rawHIDGuideLastEventTime.map { now - $0 }
			storage.rawHIDGuideLastEventTime = now
			if pressed,
			   let eventGap,
			   eventGap >= Self.rawGuideStalePressRecoveryInterval {
				let gap = String(format: "%.2f", eventGap)
				result = (
					events: [
						ControllerButtonEvent(button: .xbox, pressed: false),
						ControllerButtonEvent(button: .xbox, pressed: true),
					],
					logMessage: "Raw Guide \(source.rawValue): stale press recovered after \(gap)s quiet gap"
				)
			} else {
				result = (
					events: [],
					logMessage: "Raw Guide \(source.rawValue): duplicate \(pressed ? "press" : "release") ignored"
				)
			}
		} else {
			storage.rawHIDGuidePressed = pressed
			storage.rawHIDGuideLastEventTime = now
			result = (
				events: [ControllerButtonEvent(button: .xbox, pressed: pressed)],
				logMessage: "Raw Guide \(source.rawValue): \(pressed ? "press" : "release") routed"
			)
		}
		storage.lock.unlock()

		if let logMessage = result.logMessage {
			guideLog(logMessage)
		}
		return result.events
	}

	private nonisolated func resetRawHIDGuideButtonState() {
		storage.lock.lock()
		storage.rawHIDGuidePressed = false
		storage.rawHIDGuideLastEventTime = nil
		storage.lock.unlock()
	}

	nonisolated static func xboxElitePaddleButton(for paddleIndex: Int) -> ControllerButton? {
		switch paddleIndex {
		case 1: return .xboxPaddle1
		case 2: return .xboxPaddle2
		case 3: return .xboxPaddle3
		case 4: return .xboxPaddle4
		default: return nil
		}
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
            let steamLeftTouchPos = self.storage.steamLeftTouchpadPosition
            let steamRightTouchPos = self.storage.steamRightTouchpadPosition
            let isSteamLeftTouching = self.storage.isSteamLeftTouchpadTouching
            let isSteamRightTouching = self.storage.isSteamRightTouchpadTouching
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
                displayIsTouchpadSecondaryTouching: self.displayIsTouchpadSecondaryTouching,
                displaySteamLeftTouchpadPosition: self.displaySteamLeftTouchpadPosition,
                displaySteamRightTouchpadPosition: self.displaySteamRightTouchpadPosition,
                displayIsSteamLeftTouchpadTouching: self.displayIsSteamLeftTouchpadTouching,
                displayIsSteamRightTouchpadTouching: self.displayIsSteamRightTouchpadTouching
            )
            let sample = ControllerDisplaySample(
                leftStick: self.threadSafeLeftStick,
                rightStick: self.threadSafeRightStick,
                leftTrigger: self.threadSafeLeftTrigger,
                rightTrigger: self.threadSafeRightTrigger,
                touchpadPosition: touchPos,
                touchpadSecondaryPosition: touchSecPos,
                isTouchpadTouching: isTouching,
                isTouchpadSecondaryTouching: isSecTouching,
                steamLeftTouchpadPosition: steamLeftTouchPos,
                steamRightTouchpadPosition: steamRightTouchPos,
                isSteamLeftTouchpadTouching: isSteamLeftTouching,
                isSteamRightTouchpadTouching: isSteamRightTouching
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
            displaySteamLeftTouchpadPosition = state.displaySteamLeftTouchpadPosition
            displaySteamRightTouchpadPosition = state.displaySteamRightTouchpadPosition
            displayIsSteamLeftTouchpadTouching = state.displayIsSteamLeftTouchpadTouching
            displayIsSteamRightTouchpadTouching = state.displayIsSteamRightTouchpadTouching
            PerformanceProbe.shared.recordDisplayApply(fieldWrites: 16)
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
        if displaySteamLeftTouchpadPosition != state.displaySteamLeftTouchpadPosition {
            displaySteamLeftTouchpadPosition = state.displaySteamLeftTouchpadPosition
            fieldWrites += 1
        }
        if displaySteamRightTouchpadPosition != state.displaySteamRightTouchpadPosition {
            displaySteamRightTouchpadPosition = state.displaySteamRightTouchpadPosition
            fieldWrites += 1
        }
        if displayIsSteamLeftTouchpadTouching != state.displayIsSteamLeftTouchpadTouching {
            displayIsSteamLeftTouchpadTouching = state.displayIsSteamLeftTouchpadTouching
            fieldWrites += 1
        }
        if displayIsSteamRightTouchpadTouching != state.displayIsSteamRightTouchpadTouching {
            displayIsSteamRightTouchpadTouching = state.displayIsSteamRightTouchpadTouching
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
        displaySteamLeftTouchpadPosition = .zero
        displaySteamRightTouchpadPosition = .zero
        displayIsSteamLeftTouchpadTouching = false
        displayIsSteamRightTouchpadTouching = false
    }

    func updateBatteryInfo() {
        guard steamHIDActiveDevice == nil else {
            updateBatteryLightBar()
            return
        }

		// Xbox battery over GameController is unreliable on macOS and can report
		// 0%/.unknown before the Bluetooth Battery Service read completes.
		let isXbox = connectedController?.extendedGamepad is GCXboxGamepad
		let controllerBattery = connectedController?.battery
		if let reading = ControllerBatteryReadingResolver.resolve(
			isXbox: isXbox,
			bluetoothLevel: batteryMonitor.batteryLevel,
			bluetoothIsCharging: batteryMonitor.isCharging,
			controllerBatteryLevel: controllerBattery?.batteryLevel,
			controllerBatteryState: controllerBattery?.batteryState
		) {
			batteryLevel = reading.level
			batteryState = reading.state
		} else {
			batteryLevel = -1
			batteryState = .unknown
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
            guard self?.shouldAcceptGameControllerInput() == true else { return }
            self?.controllerQueue.async { self?.handleButton(button, pressed: pressed) }
        }
    }

    private func shouldAcceptGameControllerInput() -> Bool {
        if steamHIDActiveDevice != nil {
            return false
        }
        return !storage.lock.withLock { storage.isSteamController }
    }

    func clearGameControllerHandlers(for controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            let buttons: [GCControllerButtonInput?] = [
                gamepad.buttonA,
                gamepad.buttonB,
                gamepad.buttonX,
                gamepad.buttonY,
                gamepad.leftShoulder,
                gamepad.rightShoulder,
                gamepad.leftTrigger,
                gamepad.rightTrigger,
                gamepad.buttonMenu,
                gamepad.buttonOptions,
                gamepad.buttonHome,
                gamepad.leftThumbstickButton,
                gamepad.rightThumbstickButton,
            ]
            buttons.forEach { $0?.pressedChangedHandler = nil }
            gamepad.leftTrigger.valueChangedHandler = nil
            gamepad.rightTrigger.valueChangedHandler = nil

            for dpad in [gamepad.dpad, gamepad.leftThumbstick, gamepad.rightThumbstick] {
                dpad.valueChangedHandler = nil
                dpad.up.pressedChangedHandler = nil
                dpad.down.pressedChangedHandler = nil
                dpad.left.pressedChangedHandler = nil
                dpad.right.pressedChangedHandler = nil
            }

            if let xboxGamepad = gamepad as? GCXboxGamepad {
                let xboxButtons: [GCControllerButtonInput?] = [
                    xboxGamepad.buttonShare,
                    xboxGamepad.paddleButton1,
                    xboxGamepad.paddleButton2,
                    xboxGamepad.paddleButton3,
                    xboxGamepad.paddleButton4,
                ]
                xboxButtons.forEach { $0?.pressedChangedHandler = nil }
            }
        }

		if let microGamepad = controller.microGamepad {
			microGamepad.buttonA.pressedChangedHandler = nil
			microGamepad.buttonX.pressedChangedHandler = nil
			microGamepad.buttonMenu.pressedChangedHandler = nil
			microGamepad.dpad.valueChangedHandler = nil
			microGamepad.dpad.up.pressedChangedHandler = nil
			microGamepad.dpad.down.pressedChangedHandler = nil
			microGamepad.dpad.left.pressedChangedHandler = nil
			microGamepad.dpad.right.pressedChangedHandler = nil
		}

        let profile = controller.physicalInputProfile
        for button in profile.buttons.values {
            button.pressedChangedHandler = nil
        }
        for dpad in profile.dpads.values {
            dpad.valueChangedHandler = nil
            dpad.up.pressedChangedHandler = nil
            dpad.down.pressedChangedHandler = nil
            dpad.left.pressedChangedHandler = nil
            dpad.right.pressedChangedHandler = nil
        }
    }

	    private func setupInputHandlers(for controller: GCController) {
        // Log controller info for diagnostics (visible in Console.app)
        NSLog("[ControllerKeys] vendorName=%@  productCategory=%@  extendedGamepad=%@  microGamepad=%@",
              controller.vendorName ?? "(nil)",
              controller.productCategory,
              controller.extendedGamepad != nil ? "YES" : "NO",
              controller.microGamepad != nil ? "YES" : "NO")

			if let microGamepad = controller.microGamepad,
			   Self.isAppleTVRemoteMetadata(
				vendorName: controller.vendorName,
				productCategory: controller.productCategory
			   ) {
				setupAppleTVRemoteInputHandlers(for: controller, microGamepad: microGamepad)
				return
			}

			clearAppleTVRemoteStateForNonRemoteController()

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

		let xboxGamepad = gamepad as? GCXboxGamepad
		if xboxGamepad != nil {
			guideMonitor.startAsync()
		}
		let xboxGamepadHasPaddles = xboxGamepad.map {
			$0.paddleButton1 != nil || $0.paddleButton2 != nil || $0.paddleButton3 != nil || $0.paddleButton4 != nil
		} ?? false
		let isXboxEliteByMetadata = xboxGamepad != nil && Self.isEliteControllerMetadata(
			vendorName: controller.vendorName,
			productCategory: controller.productCategory
		)
		let isXboxEliteByHIDFallback = xboxGamepad != nil
			&& Self.shouldUseGlobalEliteHIDFallback(connectedXboxControllerCount: Self.connectedXboxControllerCount())
			&& Self.isEliteByHIDEnumeration()
		let isXboxEliteByIdentity = isXboxEliteByMetadata || isXboxEliteByHIDFallback
		let isXboxElite = xboxGamepadHasPaddles || isXboxEliteByIdentity

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
            guard self?.shouldAcceptGameControllerInput() == true else { return }
            self?.updateLeftTrigger(value, pressed: pressed)
        }
        gamepad.rightTrigger.valueChangedHandler = { [weak self] _, value, pressed in
            guard self?.shouldAcceptGameControllerInput() == true else { return }
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
		if !isXboxElite {
			bindButton(gamepad.buttonHome, to: .xbox)
		}

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

            // Log all physicalInputProfile buttons for Nintendo controllers (helps identify capture button name)
            let profileButtons = controller.physicalInputProfile.buttons.keys.sorted()
            NSLog("[ControllerKeys] Nintendo physicalInputProfile buttons: %@", profileButtons.joined(separator: ", "))
        }

        // Nintendo Pro Controller: set display name and bind capture + home buttons
        // GCExtendedGamepad doesn't reliably expose buttonHome or capture for the Pro Controller,
        // so we bind them from physicalInputProfile instead.
        if storage.lock.withLock({ storage.isNintendo && !storage.isJoyConLeft && !storage.isJoyConRight }) {
            controllerName = "Nintendo Pro Controller"

            let knownNames: Set<String> = [
                GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
                GCInputLeftShoulder, GCInputRightShoulder,
                GCInputLeftTrigger, GCInputRightTrigger,
                GCInputButtonMenu, GCInputButtonOptions,
                GCInputLeftThumbstickButton, GCInputRightThumbstickButton,
            ]

            // Home button — not exposed by GCExtendedGamepad or physicalInputProfile (macOS intercepts it).
            // Use raw HID monitoring to read it directly from the controller's input reports.
            setupNintendoHIDMonitoring()

            // Capture (screenshot) button
            if let captureButton = controller.physicalInputProfile.buttons["Button Share"] {
                bindButton(captureButton, to: .share)
                NSLog("[ControllerKeys] Nintendo capture button bound via physicalInputProfile (Button Share)")
            } else {
                // Fallback: scan for any unmapped button that might be the capture button
                let extendedKnown = knownNames.union([GCInputButtonHome])
                for (name, button) in controller.physicalInputProfile.buttons where !extendedKnown.contains(name) {
                    NSLog("[ControllerKeys] Nintendo unknown button found: %@", name)
                    bindButton(button, to: .share)
                    NSLog("[ControllerKeys] Nintendo capture button bound via unknown element: %@", name)
                    break
                }
            }
        }

		if let xboxGamepad {
            storage.lock.lock()
            storage.isDualSense = false
            storage.isDualSenseEdge = false
            storage.isDualShock = false
            storage.isNintendo = false
            storage.isJoyConLeft = false
            storage.isJoyConRight = false
            storage.isSteamController = false
            storage.lock.unlock()
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)

            // Trigger battery monitor refresh for Xbox controller
            batteryMonitor.refreshBatteryLevel()

            bindButton(xboxGamepad.buttonShare, to: .share)

            // Xbox Elite Series 2 detection:
            // 1. Paddle detection (paddles only report when no hardware profile is selected)
            // 2. PID-based detection via HID device enumeration (always works regardless of profile)
			let hasPaddles = xboxGamepadHasPaddles
			let isEliteByIdentity = isXboxEliteByIdentity

			if hasPaddles || isEliteByIdentity {
				let paddleEventSource = EliteControllerInputPolicy.paddleEventSource(
					gameControllerHasPaddles: hasPaddles
				)
                storage.lock.lock()
                storage.isXboxElite = true
				storage.elitePaddleEventSource = paddleEventSource
                storage.lock.unlock()
                UserDefaults.standard.set(true, forKey: Config.lastControllerWasXboxEliteKey)
                controllerName = "Xbox Elite Series 2 Controller"

                if hasPaddles {
                    bindButton(xboxGamepad.paddleButton1, to: .xboxPaddle1)
                    bindButton(xboxGamepad.paddleButton2, to: .xboxPaddle2)
                    bindButton(xboxGamepad.paddleButton3, to: .xboxPaddle3)
                    bindButton(xboxGamepad.paddleButton4, to: .xboxPaddle4)
                }

				// Launch helper process for Guide button and, when needed, paddle detection via raw HID.
                // gamecontrollerd blocks IOKit HID access to Elite 2 over BLE when
                // GameController.framework is loaded, so we use a separate process.
				startEliteHelper(paddleEventSource: paddleEventSource)
            } else {
                storage.lock.lock()
                storage.isXboxElite = false
				storage.elitePaddleEventSource = .none
                storage.lock.unlock()
                UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
            }
        }

        bindButton(gamepad.leftThumbstickButton, to: .leftThumbstick)
        bindButton(gamepad.rightThumbstickButton, to: .rightThumbstick)

        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard self?.shouldAcceptGameControllerInput() == true else { return }
            self?.updateLeftStick(x: xValue, y: yValue)
        }

        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, xValue, yValue in
            guard self?.shouldAcceptGameControllerInput() == true else { return }
            self?.updateRightStick(x: xValue, y: yValue)
        }

        // DualSense-specific: Touchpad support
        if let dualSenseGamepad = gamepad as? GCDualSenseGamepad {
            storage.lock.lock()
            storage.isDualSense = true
            storage.isDualShock = false
            storage.isNintendo = false
            storage.isXboxElite = false
            storage.isJoyConLeft = false
            storage.isJoyConRight = false
            storage.isSteamController = false
            storage.lock.unlock()
            UserDefaults.standard.set(true, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)

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
            storage.isXboxElite = false
            storage.isJoyConLeft = false
            storage.isJoyConRight = false
            storage.isSteamController = false
            storage.lock.unlock()
            UserDefaults.standard.set(true, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)

            setupTouchpadHandlers(
                primary: dualShockGamepad.touchpadPrimary,
                secondary: dualShockGamepad.touchpadSecondary,
                button: dualShockGamepad.touchpadButton
            )

            // Set up gyroscope gesture detection (DS4 has the same motion sensors as DualSense)
            setupMotionHandlers()

            // Set up HID monitoring for PS button
            setupPlayStationHIDMonitoring()
            startKeepAliveTimer()
        }

    }

    // MARK: - Apple TV Remote Detection

    nonisolated static func isAppleTVRemoteMetadata(vendorName: String?, productCategory: String) -> Bool {
		let remoteCategories: Set<String> = [
			GCProductCategorySiriRemote1stGen,
			GCProductCategorySiriRemote2ndGen,
			GCProductCategoryControlCenterRemote,
			GCProductCategoryCoalescedRemote,
			GCProductCategoryUniversalElectronicsRemote,
		]
		if remoteCategories.contains(productCategory) {
			return true
		}

		let combined = ((vendorName ?? "") + " " + productCategory).lowercased()
		return combined.contains("siri remote")
			|| combined.contains("apple tv remote")
			|| combined.contains("control center remote")
			|| (combined.contains("universal electronics") && combined.contains("remote"))
    }

    private func setupAppleTVRemoteInputHandlers(for controller: GCController, microGamepad: GCMicroGamepad) {
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

		controllerName = appleTVRemoteDisplayName(for: controller)

		microGamepad.allowsRotation = false
		microGamepad.reportsAbsoluteDpadValues = false

		bindButton(microGamepad.buttonA, to: .a)
		bindButton(microGamepad.buttonX, to: .x)
		bindButton(microGamepad.buttonMenu, to: .menu)
		bindButton(microGamepad.dpad.up, to: .dpadUp)
		bindButton(microGamepad.dpad.down, to: .dpadDown)
		bindButton(microGamepad.dpad.left, to: .dpadLeft)
		bindButton(microGamepad.dpad.right, to: .dpadRight)

		microGamepad.dpad.valueChangedHandler = { [weak self] _, xValue, yValue in
			guard self?.shouldAcceptGameControllerInput() == true else { return }
			self?.updateLeftStick(x: xValue, y: yValue)
		}

		bindAppleTVRemotePhysicalProfileButtons(controller.physicalInputProfile)
		setupAppleTVRemoteHIDMonitoring()

		NSLog("[ControllerKeys] Apple TV Remote detected — vendorName=%@  productCategory=%@",
			  controller.vendorName ?? "(nil)", controller.productCategory)
    }

    private func appleTVRemoteDisplayName(for controller: GCController) -> String {
		let lowercasedCategory = controller.productCategory.lowercased()
		if lowercasedCategory.contains("control center") {
			return "Apple TV Remote"
		}
		if lowercasedCategory.contains("universal electronics") {
			return "Universal Electronics Remote"
		}
		return controller.vendorName ?? controller.productCategory
    }

    private func bindAppleTVRemotePhysicalProfileButtons(_ profile: GCPhysicalInputProfile) {
		var boundNames: [String] = []
		for (name, buttonInput) in profile.buttons {
			guard let controllerButton = appleTVRemoteButton(forPhysicalInputName: name) else {
				continue
			}
			bindButton(buttonInput, to: controllerButton)
			boundNames.append("\(name)=\(controllerButton.rawValue)")
		}

		if !boundNames.isEmpty {
			NSLog("[ControllerKeys] Apple TV Remote physicalInputProfile bindings: %@",
				  boundNames.sorted().joined(separator: ", "))
		}
    }

	    private func appleTVRemoteButton(forPhysicalInputName name: String) -> ControllerButton? {
		let lowercasedName = name.lowercased()
		if lowercasedName.contains("siri")
			|| lowercasedName.contains("voice")
			|| lowercasedName.contains("dictation")
			|| lowercasedName.contains("microphone") {
			return .siri
		}
		if name == GCInputButtonHome
			|| lowercasedName.contains("home")
			|| lowercasedName.contains("tv") {
			return .xbox
		}
			return nil
	    }

	    private func clearAppleTVRemoteStateForNonRemoteController() {
			cleanupAppleTVRemoteHIDMonitoring()

				storage.lock.lock()
				storage.isAppleTVRemote = false
				storage.lock.unlock()

			UserDefaults.standard.set(false, forKey: Config.lastControllerWasAppleTVRemoteKey)
	    }

	    // MARK: - Xbox Elite Controller Detection

    nonisolated static func isEliteControllerMetadata(vendorName: String?, productCategory: String) -> Bool {
		let combined = ((vendorName ?? "") + " " + productCategory).lowercased()
		return combined.contains("elite")
	}

    nonisolated static func isSteamControllerMetadata(vendorName: String?, productCategory: String) -> Bool {
        let combined = ((vendorName ?? "") + " " + productCategory).lowercased()
        return combined.contains("steam") || combined.contains("valve")
    }

    nonisolated static func shouldUseGlobalEliteHIDFallback(connectedXboxControllerCount: Int) -> Bool {
		connectedXboxControllerCount <= 1
	}

    private static func connectedXboxControllerCount() -> Int {
		GCController.controllers().filter { $0.extendedGamepad is GCXboxGamepad }.count
	}

    /// One-shot HID enumeration to check if an Xbox Elite Series 2 is connected by PID.
    /// Used only when a single Xbox controller is connected so it cannot classify the wrong active controller.
    private static func isEliteByHIDEnumeration() -> Bool {
        guard let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone)) as IOHIDManager? else {
            return false
        }
        let matching = [kIOHIDVendorIDKey: 0x045E] as CFDictionary
        IOHIDManagerSetDeviceMatching(manager, matching)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return false }
        for device in devices {
            if let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int,
               XboxGuideMonitor.eliteSeries2PIDs.contains(pid) {
                return true
            }
        }
        return false
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
        storage.isXboxElite = false
        storage.isSteamController = false
        storage.lock.unlock()

        UserDefaults.standard.set(true, forKey: Config.lastControllerWasNintendoKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)
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
        LatencyDiagnostics.mark("controller.handleButton \(button.rawValue) pressed=\(pressed)")
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
        let shouldBypassChordWindow = storage.lowLatencyInputEnabled
            && !storage.chordParticipantButtons.contains(button)
            && storage.capturedButtonsInWindow.isEmpty
        if shouldBypassChordWindow {
            let callback = storage.onButtonPressed
            let uiButtons = storage.activeButtons
            storage.lock.unlock()

            Task { @MainActor in
                self.activeButtons = uiButtons
            }

            LatencyDiagnostics.mark("controller.lowLatencyPress \(button.rawValue)")
            callback?(button)
            return
        }

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
            LatencyDiagnostics.mark("controller.chord \(captured.map(\.rawValue).sorted().joined(separator: "+"))")
            chordCallback?(captured)
        } else if let button = captured.first {
            LatencyDiagnostics.mark("controller.delayedPress \(button.rawValue)")
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
