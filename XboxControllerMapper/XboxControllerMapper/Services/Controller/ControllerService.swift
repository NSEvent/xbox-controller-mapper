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
    /// Non-nil when the connected pad is one of the small 8BitDo models
    /// (drives the dedicated minimap preview).
    var eightBitDoModel: EightBitDoMinimapModel?
    /// D-pad buttons we emitted (as real .dpad* presses) before the stickless
    /// clone detector latched. Tracked so a release arriving after the latch
    /// still fires, instead of leaving a button stuck down.
    var emittedCloneDpadButtons: Set<ControllerButton> = []
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
	    // 8BitDo D-input (Android-mode) HID button state — Home + Star, which the
	    // GameController profile omits, are read from raw HID instead.
	    var lastEightBitDoHomeState: Bool = false
	    var lastEightBitDoStarState: Bool = false
	    var appleTVRemoteTouchReleaseWorkItem: DispatchWorkItem?
    var appleTVRemoteActiveSystemKeyTypes: Set<Int> = []
    var appleTVRemoteSystemKeyTypeSuppressUntil: [Int: TimeInterval] = [:]
    var appleTVRemoteActiveButtonUsages: [ControllerButton: Set<UInt64>] = [:]
    var appleTVRemoteButtonReleaseWorkItems: [ControllerButton: DispatchWorkItem] = [:]
	var hasAppleTVRemoteHIDActivationDevice: Bool = false
    var appleTVRemoteCircularScrollActive: Bool = false
    var appleTVRemoteCircularScrollStartedInOuterRing: Bool = false

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

    // Typed event boundary consumed by MappingEngine.
    var onInputEvent: ((ControllerInputEvent) -> Void)?
    /// When true, region-click events only fire while a finger is currently touching
    /// the pad. Default true. Mirrors `JoystickSettings.requireActiveTouchForRegionClick`
    /// and is updated by MappingEngine whenever joystick settings change.
    var requireActiveTouchForRegionClick: Bool = true

    /// Mirrors `JoystickSettings.appleTVRemoteCircularScrollEnabled`.
    /// Read by the Apple TV clickpad classifier before it takes ownership
    /// of touch movement for circular edge scrolling.
    var appleTVRemoteCircularScrollEnabled: Bool = true

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
    var steamGyroYawBiasSum: Double = 0
    var steamGyroBiasSampleCount: Int = 0
    var steamGyroPitchBias: Double = 0
    var steamGyroRollBias: Double = 0
    var steamGyroYawBias: Double = 0
    var steamGyroBiasCalibrationNotBefore: TimeInterval = 0
    var steamGyroLastRawPitch: Double?
    var steamGyroLastRawRoll: Double?
    var steamGyroLastRawYaw: Double?
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
	@Published var controllerMappingSource: String?

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
	private var configuredGameControllerIDs: Set<ObjectIdentifier> = []
	private let inactiveControllerAnalogActivationDeadzone: Float = 0.18
	private let inactiveControllerTakeoverQuietInterval: TimeInterval = 0.75
	private var activeGameControllerLastInputTime: TimeInterval = 0

    /// Generation token for the battery polling chain. `updateBatteryInfo()` bumps
    /// it so previously scheduled polls cancel themselves — otherwise every external
    /// trigger (connect, BLE battery publish, charging transition) would spawn
    /// another immortal `asyncAfter` chain. Internal for test visibility.
    var batteryPollGeneration: UInt64 = 0

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
    /// Device the pending `genericHIDFallbackTimer` was armed for, so removal of
    /// that device can cancel the timer before it promotes a vanished device.
    var genericHIDPendingFallbackDevice: IOHIDDevice?
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
    var nintendoHIDRegistrations: [NintendoHIDRegistration] = []

    // 8BitDo D-input pad HID monitoring (Home + Star not exposed by GameController)
    var eightBitDoHIDManager: IOHIDManager?
    var eightBitDoHIDRegistrations: [EightBitDoHIDRegistration] = []

    /// Detects a stickless d-pad clone (8BitDo Zero 2 impersonating a Pro
    /// Controller in Switch mode or a DualShock 4 in Mac mode) from input
    /// behavior alone — no reliance on the unreliable HID manufacturer string.
    /// `nonisolated` + internally locked so HID callbacks and GameController
    /// handlers on different queues can feed it. See [[SticklessDpadCloneDetector]].
    nonisolated let sticklessCloneDetector = SticklessDpadCloneDetector()

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

	nonisolated var threadSafeControllerPresentationState: ControllerPresentationState {
		storage.lock.lock()
		defer { storage.lock.unlock() }
		return storage.controllerPresentationStateLocked
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
		var isSteamController: Bool = false
    }

    /// Captures a consistent snapshot of all joystick-polling-relevant state in a single lock acquisition.
    /// This replaces 4-6 individual `threadSafe*` property reads that each acquire/release the lock separately.
	nonisolated func snapshot() -> ControllerSnapshot {
		storage.lock.lock()
		defer { storage.lock.unlock() }
		let presentationState = storage.controllerPresentationStateLocked
		return ControllerSnapshot(
			leftStick: storage.leftStick,
			rightStick: storage.rightStick,
			leftTrigger: storage.leftTrigger,
			rightTrigger: storage.rightTrigger,
			touchpadPosition: storage.touchpadPosition,
			isTouchpadTouching: storage.isTouchpadTouching,
			hasMotion: presentationState.hasMotion,
			isSteamController: presentationState.isSteamController
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
		threadSafeControllerPresentationState.isDualSense
	}

	nonisolated var threadSafeIsDualSenseEdge: Bool {
		threadSafeControllerPresentationState.isDualSenseEdge
	}

	nonisolated var threadSafeIsDualShock: Bool {
		threadSafeControllerPresentationState.isDualShock
	}

	/// Returns true if connected controller is any PlayStation controller (DualSense, DualShock)
	nonisolated var threadSafeIsPlayStation: Bool {
		threadSafeControllerPresentationState.isPlayStation
	}

	nonisolated var threadSafeHasMotion: Bool {
		threadSafeControllerPresentationState.hasMotion
	}

	nonisolated var threadSafeIsNintendo: Bool {
		threadSafeControllerPresentationState.isNintendo
	}

	nonisolated var threadSafeEightBitDoMinimapModel: EightBitDoMinimapModel? {
		threadSafeControllerPresentationState.eightBitDoModel
	}

    /// True for a stickless Nintendo-clone whose d-pad is funneled through the
    /// (mis-calibrated) phantom left stick — we drive the left stick from raw
    /// HID instead, so the GameController left-thumbstick must be ignored.
    /// Detected behaviorally (see [[SticklessDpadCloneDetector]]); gated to the
    /// Nintendo path since the DualShock clone's GameController stick is fine.
	nonisolated var threadSafeIsNintendoDPadStickClone: Bool {
		guard sticklessCloneDetector.isSticklessClone else { return false }
		return threadSafeControllerPresentationState.isNintendo
	}

	nonisolated var threadSafeIsXboxElite: Bool {
		threadSafeControllerPresentationState.isXboxElite
	}

	nonisolated var threadSafeIsSteamController: Bool {
		threadSafeControllerPresentationState.isSteamController
	}

	nonisolated var threadSafeIsAppleTVRemote: Bool {
		threadSafeControllerPresentationState.isAppleTVRemote
	}

	/// Returns true if a single Joy-Con is connected (left or right, not a Pro Controller)
	nonisolated var threadSafeIsSingleJoyCon: Bool {
		threadSafeControllerPresentationState.isSingleJoyCon
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
    var displayUpdateTimer: DispatchSourceTimer?
    var displayTimerSuspended = false
    var windowVisibilityObservers: [NSObjectProtocol] = []

    /// Battery level (0 to 1)
    @Published var batteryLevel: Float = -1

    /// Battery state
    @Published var batteryState: GCDeviceBattery.State = .unknown

    // Typed input event sink (Thread-safe storage backing)
    var onInputEvent: ((ControllerInputEvent) -> Void)? {
        get { readStorage(\.onInputEvent) }
        set { writeStorage(\.onInputEvent, newValue) }
    }
    var requireActiveTouchForRegionClick: Bool {
        get { readStorage(\.requireActiveTouchForRegionClick) }
        set { writeStorage(\.requireActiveTouchForRegionClick, newValue) }
    }
    var appleTVRemoteCircularScrollEnabled: Bool {
		get { readStorage(\.appleTVRemoteCircularScrollEnabled) }
		set { writeStorage(\.appleTVRemoteCircularScrollEnabled, newValue) }
    }
    var touchpadInputMode: TouchpadInputMode {
        get { readStorage(\.touchpadInputMode) }
        set { writeStorage(\.touchpadInputMode, newValue) }
    }
    nonisolated func emitInputEvent(_ event: ControllerInputEvent) {
        let callback = readStorage(\.onInputEvent)
        callback?(event)
    }

    private var cancellables = Set<AnyCancellable>()

    /// Retained copy of the init-time flag so the permission-gated startups
    /// (`startBluetoothBattery`, `startInputMonitoringHID`) can respect
    /// screenshot/test mode when called later from the onboarding flow.
    private let hardwareMonitoringEnabled: Bool

    /// Guards so the deferred, permission-gated startups are idempotent — they
    /// may run at launch (returning user, permission already granted) or be
    /// triggered once by the onboarding grant hooks, but never both.
    private var bluetoothBatteryStarted = false
    private var inputMonitoringHIDStarted = false

    // Low-level monitor for Xbox Guide button
	private let guideMonitor: XboxGuideMonitor

    // Low-level monitor for Battery (Bluetooth Workaround for macOS/Xbox issue)
    let batteryMonitor = BluetoothBatteryMonitor()

    // Haptic engines for controller feedback (try multiple localities)
    // Protected by hapticLock — accessed from both @MainActor (setup/stop) and hapticQueue (play)
    let hapticLock = NSLock()
    nonisolated(unsafe) var hapticEngines: [CHHapticEngine] = []
    let hapticQueue = DispatchQueue(label: "com.xboxmapper.haptic", qos: .userInitiated)
    let hapticQueueSpecificKey = DispatchSpecificKey<Void>()
    struct ActiveHapticPlayer {
        let player: CHHapticPatternPlayer
        let endTime: TimeInterval
    }
    nonisolated(unsafe) var activeHapticPlayers: [ActiveHapticPlayer] = []
    nonisolated(unsafe) var hapticSessionGeneration: UInt64 = 0
	#if DEBUG
	nonisolated(unsafe) var hapticSessionAcceptedForTesting: ((UInt64) -> Void)?
	#endif

    /// Display name shown in the toolbar pill for `--screenshot-variant` captures.
    static func screenshotControllerName(for variant: String) -> String {
        switch variant {
        case "dualsense": return "DualSense Wireless Controller"
        case "dualsense-edge": return "DualSense Edge Wireless Controller"
        case "dualshock": return "DUALSHOCK 4 Wireless Controller"
        case "xbox-elite": return "Xbox Elite Wireless Controller"
        case "nintendo": return "Pro Controller"
        case "steam": return "Steam Controller"
        case "appletv": return "Apple TV Remote"
        case "8bitdo-zero2": return "8BitDo Zero 2 gamepad"
        case "8bitdo-micro": return "8BitDo Micro gamepad"
        case "8bitdo-lite2": return "8BitDo Lite 2"
        case "8bitdo-lite-se": return "8BitDo Lite SE"
        default: return "Xbox Wireless Controller"
        }
    }

    /// Identifies the small 8BitDo pads from their SDL/HID product names
    /// ("8BitDo Zero 2", "8BitDo Micro", "8BitDo Lite 2", "8BitDo Lite SE").
    nonisolated static func eightBitDoMinimapModel(forControllerName name: String) -> EightBitDoMinimapModel? {
        let lowered = name.lowercased()
        guard lowered.contains("8bitdo") else { return nil }
        if lowered.contains("zero") { return .zero2 }
        if lowered.contains("micro") { return .micro }
        if lowered.contains("lite se") { return .liteSE }
        if lowered.contains("lite") { return .lite2 }
        return nil
    }

	nonisolated static func eightBitDoMinimapModel(vendorName: String?, productCategory: String) -> EightBitDoMinimapModel? {
		eightBitDoMinimapModel(forControllerName: "\(vendorName ?? "") \(productCategory)")
	}

	nonisolated static func isSticklessEightBitDoModel(vendorName: String?, productCategory: String) -> Bool {
		eightBitDoMinimapModel(vendorName: vendorName, productCategory: productCategory)?.isStickless == true
	}

	nonisolated static func shouldUsePhysicalDirectionPadAsLeftStickFallback(
		vendorName: String?,
		productCategory: String
	) -> Bool {
		!isSticklessEightBitDoModel(vendorName: vendorName, productCategory: productCategory)
	}

	private func startEightBitDoHIDMonitoringIfNeeded(for controller: GCController, reason: String) {
		guard Self.eightBitDoMinimapModel(
			vendorName: controller.vendorName,
			productCategory: controller.productCategory
		) != nil else { return }

		guard SystemPermission.inputMonitoringGranted else {
			NSLog("[ControllerKeys] 8BitDo HID monitoring deferred (%@); Input Monitoring is not granted", reason)
			return
		}

		setupEightBitDoHIDMonitoring()
	}

    /// Starts CoreBluetooth battery monitoring. Constructing the
    /// `CBCentralManager` (inside `BluetoothBatteryMonitor.startMonitoring`) is
    /// what triggers the Bluetooth system prompt, so this is deferred for new
    /// users until the onboarding Bluetooth step. Run at launch only if the
    /// permission is already granted. Idempotent.
    func startBluetoothBattery() {
        guard hardwareMonitoringEnabled, !bluetoothBatteryStarted else { return }
        bluetoothBatteryStarted = true
        batteryMonitor.startMonitoring()
        batteryMonitor.$batteryLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateBatteryInfo()
            }
            .store(in: &cancellables)
    }

    /// Starts IOHIDManager-based input monitoring (Steam controllers, generic
    /// HID gamepads, the Apple TV remote). Opening an `IOHIDManager` triggers the
    /// Input Monitoring system prompt, so this is deferred for new users until
    /// the onboarding Input Monitoring step. Run at launch only if the permission
    /// is already granted. Also (re)starts the Xbox guide monitor when a
    /// controller is connected, so a late grant takes effect without needing a
    /// reconnect. Idempotent.
    func startInputMonitoringHID() {
        guard hardwareMonitoringEnabled, !inputMonitoringHIDStarted else { return }
        inputMonitoringHIDStarted = true
        setupSteamControllerHIDMonitoring()
        setupGenericHIDMonitoring()
        setupAppleTVRemoteHIDMonitoring()
		if let connectedController {
			startEightBitDoHIDMonitoringIfNeeded(for: connectedController, reason: "input monitoring start")
		}
        if isConnected {
            guideMonitor.startAsync()
        }
    }

    init(enableHardwareMonitoring: Bool = true) {
        let shouldEnableHardwareMonitoring = enableHardwareMonitoring && !Self.isRunningTests
		self.guideMonitor = XboxGuideMonitor(enableHardwareMonitoring: shouldEnableHardwareMonitoring)
        self.hardwareMonitoringEnabled = shouldEnableHardwareMonitoring
		hapticQueue.setSpecific(key: hapticQueueSpecificKey, value: ())

		// Load last controller type (so UI shows correct button labels when no controller is connected)
		storage.restoreControllerTypeFlags(
			isDualSense: UserDefaults.standard.bool(forKey: Config.lastControllerWasDualSenseKey),
			isDualSenseEdge: UserDefaults.standard.bool(forKey: Config.lastControllerWasDualSenseEdgeKey),
			isDualShock: UserDefaults.standard.bool(forKey: Config.lastControllerWasDualShockKey),
			isNintendo: UserDefaults.standard.bool(forKey: Config.lastControllerWasNintendoKey),
			isXboxElite: UserDefaults.standard.bool(forKey: Config.lastControllerWasXboxEliteKey),
			isSteamController: UserDefaults.standard.bool(forKey: Config.lastControllerWasSteamControllerKey),
			isAppleTVRemote: UserDefaults.standard.bool(forKey: Config.lastControllerWasAppleTVRemoteKey)
		)

        // Screenshot mode: force the preview to the requested variant and
        // present as connected. Hardware monitoring is off in this mode (see
        // ServiceContainer), so nothing can override these between captures.
        if let variant = AppRuntime.screenshotVariant {
            if let type = ControllerTypeState(screenshotVariant: variant) {
                storage.applyControllerTypeLocked(type)
            }
            storage.eightBitDoModel = {
                switch variant {
                case "8bitdo-zero2": return .zero2
                case "8bitdo-micro": return .micro
                case "8bitdo-lite2": return .lite2
                case "8bitdo-lite-se": return .liteSE
                default: return nil
                }
            }()
            isConnected = true
            controllerName = Self.screenshotControllerName(for: variant)
            // A believable battery reading instead of the "?" unknown pill
            batteryLevel = 0.85
            batteryState = .discharging
            // Show the controller "in use" (lit button, deflected stick,
            // pulled trigger); --screenshot-animate runs a scripted input
            // loop on top for GIF/video recordings.
            applyScreenshotDemoPose()
            if AppRuntime.screenshotAnimate {
                startScreenshotDemoAnimation()
            }
        }

        if shouldEnableHardwareMonitoring {
            GCController.shouldMonitorBackgroundEvents = true
            setupNotifications()
            startDiscovery()
            checkConnectedControllers()

            // Bluetooth battery monitoring and IOHID-based input monitoring each
            // trigger a system permission prompt the first time they start. To
            // avoid the old launch-time prompt-wall, only start them here when
            // the user has *already* granted the permission (returning users).
            // For new users the onboarding flow starts them once the relevant
            // step is granted (see startBluetoothBattery / startInputMonitoringHID).
            if SystemPermission.bluetoothGranted {
                startBluetoothBattery()
            }
            if SystemPermission.inputMonitoringGranted {
                startInputMonitoringHID()
            }
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
		for controller in GCController.controllers() {
			clearGameControllerHandlers(for: controller)
		}
		configuredGameControllerIDs.removeAll()
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
				if let controller = notification.object as? GCController {
                    // Guard against late/out-of-order disconnect notifications.
                    // During Bluetooth reconnect macOS may reuse the same GCController
                    // object and deliver didDisconnect AFTER didConnect. Check the
                    // system controller list to verify the controller is actually gone.
                    if GCController.controllers().contains(controller) {
                        NSLog("[ControllerKeys] Ignoring stale disconnect (gen=%llu) — controller still in system list",
                              self.connectionGeneration)
                        return
                    }
					if controller == self.connectedController {
						NSLog("[ControllerKeys] controllerDisconnected — generation=%llu", self.connectionGeneration)
						self.activeGameControllerDisconnected(controller)
					} else {
						self.clearGameControllerHandlers(for: controller)
						self.configuredGameControllerIDs.remove(ObjectIdentifier(controller))
						self.objectWillChange.send()
					}
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
		let controllers = GCController.controllers()
		for controller in controllers {
			installGameControllerHandlersIfNeeded(for: controller)
		}
		if let controller = controllers.first {
			activateGameController(controller, reason: "startup")
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

		installGameControllerHandlersIfNeeded(for: controller)
		activateGameController(controller, reason: "connect")
    }

	private func installGameControllerHandlersIfNeeded(for controller: GCController) {
		let controllerID = ObjectIdentifier(controller)
		guard !configuredGameControllerIDs.contains(controllerID) else { return }
		setupInputHandlers(for: controller)
		configuredGameControllerIDs.insert(controllerID)
	}

	func activateGameController(_ controller: GCController, reason: String) {
		if steamHIDActiveDevice != nil {
			NSLog("[ControllerKeys] Ignoring GameController activation while Steam Controller raw HID is active")
			return
		}
		if Self.isSteamControllerMetadata(
			vendorName: controller.vendorName,
			productCategory: controller.productCategory
		) {
			NSLog("[ControllerKeys] Ignoring Steam Controller GameController activation; raw HID owns Steam input")
			return
		}
		if connectedController === controller,
		   storage.lock.withLock({ !storage.isAppleTVRemote }) {
			return
		}

        connectionGeneration += 1
		NSLog("[ControllerKeys] controllerActivated — generation=%llu reason=%@ vendor=%@",
			  connectionGeneration, reason, controller.vendorName ?? "(nil)")

		prepareForActiveControllerSwitch()
		activeGameControllerLastInputTime = CFAbsoluteTimeGetCurrent()

        // Cancel generic HID fallback if GameController framework claimed this device
        genericHIDFallbackTimer?.cancel()
        genericHIDFallbackTimer = nil
        genericHIDPendingFallbackDevice = nil
        if genericHIDController != nil {
            genericHIDController?.stop()
            genericHIDController = nil
            isGenericController = false
        }
        connectedController = controller
		controllerName = ControllerIdentityResolver.displayName(
			vendorName: controller.vendorName,
			productCategory: controller.productCategory
		)
		controllerMappingSource = nil
        currentControllerIdentity = nil

        storage.lock.lock()
        resetTouchpadStateLocked()
        storage.lock.unlock()

        setupInputHandlers(for: controller)
		configuredGameControllerIDs.insert(ObjectIdentifier(controller))
        setupHaptics(for: controller)
        if currentControllerIdentity == nil {
            currentControllerIdentity = ControllerIdentityResolver.identity(
                for: controller,
                preferredDevice: hidDevice
            )
        }

        // Small 8BitDo pads in D-input (Android) mode expose their real
        // product name through GameController too. In Switch/macOS modes
        // they are byte-perfect Pro Controller / DualShock clones, so they
        // keep those previews (pin the model via the preview dropdown).
		if let model = Self.eightBitDoMinimapModel(
			vendorName: controller.vendorName,
			productCategory: controller.productCategory
		) {
            storage.lock.lock()
            storage.eightBitDoModel = model
            storage.lock.unlock()
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

		let activationGeneration = connectionGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
			guard let self, self.connectionGeneration == activationGeneration else { return }
			self.playHaptic(intensity: 0.7, sharpness: 0.6, duration: 0.12)
        }
        updateBatteryInfo()
        startDisplayUpdateTimer()
    }

	private func activeGameControllerDisconnected(_ controller: GCController) {
		clearGameControllerHandlers(for: controller)
		configuredGameControllerIDs.remove(ObjectIdentifier(controller))
		if let nextController = GCController.controllers().first(where: { $0 !== controller }) {
			activateGameController(nextController, reason: "active disconnect")
		} else {
			controllerDisconnected()
		}
	}

	func prepareForActiveControllerSwitch() {
		let wasAppleTVRemote = storage.lock.withLock { storage.isAppleTVRemote }
		if wasAppleTVRemote {
			releaseAppleTVRemoteButtonsIfNeeded()
			releaseAppleTVRemoteTouchIfStillActive()
		}

		let buttonsToRelease = storage.lock.withLock { Array(storage.activeButtons) }
		for button in buttonsToRelease {
			handleButton(button, pressed: false)
		}

		connectedController?.motion?.sensorsActive = false
		stopKeepAliveTimer()
		stopBatteryBlink()
		stopChargingAnim()
		stopHaptics()
		cleanupHIDMonitoring()
		cleanupNintendoHIDMonitoring()
		cleanupEightBitDoHIDMonitoring()
		stopEliteHelper()
		controllerMappingSource = nil
		activeGameControllerLastInputTime = 0

		activeButtons.removeAll()
		leftStick = .zero
		rightStick = .zero
		leftTriggerValue = 0
		rightTriggerValue = 0

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
		resetTouchpadStateLocked()
		resetMotionStateLocked()
		storage.lastMicButtonState = false
		storage.lastPSButtonState = false
		storage.lastNintendoHomeState = false
		storage.lastHIDBatteryCharging = nil
		storage.lastLeftPaddleState = false
		storage.lastRightPaddleState = false
		storage.lastLeftFunctionState = false
		storage.lastRightFunctionState = false
		storage.elitePaddleEventSource = .none
		storage.eliteRawPaddleState.removeAll()
		storage.rawHIDGuidePressed = false
		storage.rawHIDGuideLastEventTime = nil
		// Clear stickless-clone / 8BitDo state here too: switching directly to
		// the Apple TV Remote goes through this method but bypasses
		// resetControllerTypeState(), so without this a prior clone pad's
		// detection state and minimap model would leak into the next controller.
		resetCloneDetectionStateLocked()
		storage.lock.unlock()

		// Detector has its own lock — reset outside storage.lock to keep the
		// lock-acquisition order consistent.
		sticklessCloneDetector.reset()
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
		configuredGameControllerIDs.removeAll()
		activeGameControllerLastInputTime = 0
        isConnected = false
        currentControllerIdentity = nil
        isGenericController = false
        controllerName = ""
		controllerMappingSource = nil
        activeButtons.removeAll()
        leftStick = .zero
        rightStick = .zero
        batteryLevel = -1
        batteryState = .unknown
        batteryMonitor.resetBatteryLevel()  // Clear stale battery reading
        batteryMonitor.allowsSerialNamedPeripherals = false
        stopDisplayUpdateTimer()
        stopKeepAliveTimer()
        stopBatteryBlink()
        stopChargingAnim()
        stopHaptics()
        cleanupHIDMonitoring()  // Clean up mic button monitoring
        cleanupNintendoHIDMonitoring()  // Clean up Nintendo Home button monitoring
        cleanupEightBitDoHIDMonitoring()  // Clean up 8BitDo Home/Star monitoring
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
		storage.appleTVRemoteCircularScrollActive = false
		storage.appleTVRemoteCircularScrollStartedInOuterRing = false
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

    // MARK: - Input Handlers

    /// Helper to bind a GCControllerButtonInput to a ControllerButton
	private func bindButton(_ element: GCControllerButtonInput?, to button: ControllerButton, from controller: GCController) {
		element?.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
			guard let controller else { return }
			self?.routeGameControllerButtonInput(from: controller, button: button, pressed: pressed)
        }
    }

	/// D-pad binding for clone-capable controllers (Nintendo / DualShock). Feeds
	/// the stickless-clone detector and, once a clone is confirmed, suppresses
	/// the direct .dpad* mapping so the d-pad (which the clone also routes to the
	/// left stick) is governed by the stick mode instead. Genuine controllers
	/// never latch as clones, so the press passes straight through.
	private func bindCloneAwareDpad(_ element: GCControllerButtonInput?, to button: ControllerButton, from controller: GCController) {
		element?.pressedChangedHandler = { [weak self, weak controller] _, _, pressed in
			guard let self, let controller else { return }

			if self.sticklessCloneDetector.isSticklessClone {
				// Clone confirmed: the left stick already carries this d-pad.
				// Suppress the press, but still deliver a release for any press
				// that fired before the latch so nothing stays stuck down.
				let shouldRelease: Bool = self.storage.lock.withLock {
					guard !pressed, self.storage.emittedCloneDpadButtons.contains(button) else { return false }
					self.storage.emittedCloneDpadButtons.remove(button)
					return true
				}
				if shouldRelease {
					self.routeGameControllerButtonInput(from: controller, button: button, pressed: false)
				}
				return
			}

			// Not (yet) a clone — behave like a normal d-pad button, tracking
			// emitted presses so a post-latch release can still be delivered.
			self.storage.lock.withLock {
				if pressed { self.storage.emittedCloneDpadButtons.insert(button) }
				else { self.storage.emittedCloneDpadButtons.remove(button) }
			}
			self.routeGameControllerButtonInput(from: controller, button: button, pressed: pressed)
		}
	}

	private func routeGameControllerButtonInput(from controller: GCController, button: ControllerButton, pressed: Bool) {
		Task { @MainActor [weak self, weak controller] in
			guard let self, let controller else { return }
			guard self.prepareGameControllerInput(from: controller, meaningful: pressed) else { return }
			self.controllerQueue.async { [weak self] in
				self?.handleButton(button, pressed: pressed)
			}
		}
	}

	private func routeGameControllerStickInput(
		from controller: GCController,
		x: Float,
		y: Float,
		update: @escaping (ControllerService, Float, Float) -> Void
	) {
		let meaningful = hypotf(x, y) >= inactiveControllerAnalogActivationDeadzone
		Task { @MainActor [weak self, weak controller] in
			guard let self, let controller else { return }
			guard self.prepareGameControllerInput(from: controller, meaningful: meaningful) else { return }
			update(self, x, y)
		}
	}

	private func routeGameControllerTriggerInput(
		from controller: GCController,
		value: Float,
		pressed: Bool,
		update: @escaping (ControllerService, Float, Bool) -> Void
	) {
		let meaningful = pressed || value >= inactiveControllerAnalogActivationDeadzone
		Task { @MainActor [weak self, weak controller] in
			guard let self, let controller else { return }
			guard self.prepareGameControllerInput(from: controller, meaningful: meaningful) else { return }
			update(self, value, pressed)
		}
	}

	func routeGameControllerTouchpadInput(
		from controller: GCController,
		meaningful: Bool,
		update: @escaping (ControllerService) -> Void
	) {
		Task { @MainActor [weak self, weak controller] in
			guard let self, let controller else { return }
			guard self.prepareGameControllerInput(from: controller, meaningful: meaningful) else { return }
			update(self)
		}
	}

    private func shouldAcceptGameControllerInput() -> Bool {
        if steamHIDActiveDevice != nil {
            return false
        }
        return !storage.lock.withLock { storage.isSteamController }
    }

	private func prepareGameControllerInput(from controller: GCController, meaningful: Bool) -> Bool {
		if steamHIDActiveDevice != nil {
			return false
		}
		let now = CFAbsoluteTimeGetCurrent()
		if connectedController !== controller {
			guard Self.shouldActivateInactiveControllerInput(
				meaningful: meaningful,
				activeControllerHasInput: hasActiveGameControllerInput(),
				activeControllerLastInputTime: activeGameControllerLastInputTime,
				now: now,
				quietInterval: inactiveControllerTakeoverQuietInterval
			) else { return false }
			activateGameController(controller, reason: "input")
		} else {
			if meaningful || hasActiveGameControllerInput() {
				activeGameControllerLastInputTime = now
			}
		}
		return shouldAcceptGameControllerInput()
	}

	nonisolated static func shouldActivateInactiveControllerInput(
		meaningful: Bool,
		activeControllerHasInput: Bool,
		activeControllerLastInputTime: TimeInterval,
		now: TimeInterval,
		quietInterval: TimeInterval
	) -> Bool {
		guard meaningful else { return false }
		guard !activeControllerHasInput else { return false }
		guard activeControllerLastInputTime > 0 else { return true }
		return now - activeControllerLastInputTime >= quietInterval
	}

	nonisolated func hasActiveGameControllerInput() -> Bool {
		storage.lock.lock()
		defer { storage.lock.unlock() }
		return Self.hasActiveGameControllerInput(
			activeButtons: storage.activeButtons,
			leftStick: storage.leftStick,
			rightStick: storage.rightStick,
			leftTrigger: storage.leftTrigger,
			rightTrigger: storage.rightTrigger,
			touchpadIsActive: storage.isTouchpadTouching ||
				storage.isTouchpadSecondaryTouching ||
				storage.isSteamLeftTouchpadTouching ||
				storage.isSteamRightTouchpadTouching,
			deadzone: inactiveControllerAnalogActivationDeadzone
		)
	}

	nonisolated static func hasActiveGameControllerInput(
		activeButtons: Set<ControllerButton>,
		leftStick: CGPoint,
		rightStick: CGPoint,
		leftTrigger: Float,
		rightTrigger: Float,
		touchpadIsActive: Bool,
		deadzone: Float
	) -> Bool {
		guard activeButtons.isEmpty else { return true }
		guard !touchpadIsActive else { return true }
		if hypotf(Float(leftStick.x), Float(leftStick.y)) >= deadzone { return true }
		if hypotf(Float(rightStick.x), Float(rightStick.y)) >= deadzone { return true }
		if leftTrigger >= deadzone || rightTrigger >= deadzone { return true }
		return false
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

    /// Clears every controller-type flag (and the matching UserDefaults keys) so
    /// detection branches only ever have to set their own type. Without this, a
    /// controller matching none of the branches keeps stale flags loaded in init.
    /// Note: Apple TV Remote HID *cleanup* stays owned by
    /// clearAppleTVRemoteStateForNonRemoteController — only the flag resets here.
    /// Single source of truth for the per-connection stickless-clone / 8BitDo
    /// detection storage fields. Caller MUST hold `storage.lock`; pair with
    /// `sticklessCloneDetector.reset()` after unlocking. Both
    /// `resetControllerTypeState()` and `prepareForActiveControllerSwitch()`
    /// use this so a new clone-detection field can't be reset on one path but
    /// leaked on the other.
    // Internal (not private) so a unit test can exercise it directly: calling
    // the full prepareForActiveControllerSwitch()/resetControllerTypeState() on a
    // bare service tears down HID monitoring that was never set up.
    func resetCloneDetectionStateLocked() {
        storage.eightBitDoModel = nil
        storage.emittedCloneDpadButtons.removeAll()
    }

    func resetControllerTypeState() {
        storage.lock.lock()
        storage.clearControllerTypeFlagsLocked()
        resetCloneDetectionStateLocked()
        storage.elitePaddleEventSource = .none
        storage.lock.unlock()

        // Behavioral clone detection is per-connection — start fresh.
        sticklessCloneDetector.reset()

        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)
        UserDefaults.standard.set(false, forKey: Config.lastControllerWasAppleTVRemoteKey)
    }

	    private func setupInputHandlers(for controller: GCController) {
        // Log controller info for diagnostics (visible in Console.app)
        NSLog("[ControllerKeys] vendorName=%@  productCategory=%@  extendedGamepad=%@  microGamepad=%@",
              controller.vendorName ?? "(nil)",
              controller.productCategory,
              controller.extendedGamepad != nil ? "YES" : "NO",
              controller.microGamepad != nil ? "YES" : "NO")

        // Reset all controller-type flags before detection. A controller that
        // matches none of the branches below (a plain MFi pad like Backbone or
        // Nimbus) would otherwise keep the flags loaded from UserDefaults in init.
        resetControllerTypeState()

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

        // 8BitDo D-input pads (Micro / Zero 2 / Lite, Android mode) expose Home
        // and Star only via raw HID — the GameController profile drops them.
        // Monitor the underlying 0x2DC8 device directly, regardless of which
        // GameController path the pad takes. No-op in Switch mode (VID 0x057E,
        // handled by the Nintendo HID path instead).
		startEightBitDoHIDMonitoringIfNeeded(for: controller, reason: "controller setup")

        // Try extendedGamepad first (works for Xbox, DualSense, Pro Controller, paired Joy-Cons)
        guard let gamepad = controller.extendedGamepad else {
            // Single Joy-Cons don't expose extendedGamepad or microGamepad — they only
            // provide physicalInputProfile. Use it to dynamically bind available elements.
            NSLog("[ControllerKeys] No extendedGamepad — using physicalInputProfile fallback")
			setupPhysicalInputProfileHandlers(controller.physicalInputProfile, from: controller)
            return
        }

		let xboxGamepad = gamepad as? GCXboxGamepad
		// Opening the guide monitor's IOHIDManager needs Input Monitoring. Skip it
		// until that's granted so a connected Xbox pad can't cold-trigger the
		// prompt before onboarding; startInputMonitoringHID() starts it post-grant.
		if xboxGamepad != nil, SystemPermission.inputMonitoringGranted {
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
		bindButton(gamepad.buttonA, to: .a, from: controller)
		bindButton(gamepad.buttonB, to: .b, from: controller)
		bindButton(gamepad.buttonX, to: .x, from: controller)
		bindButton(gamepad.buttonY, to: .y, from: controller)

        // Bumpers
		bindButton(gamepad.leftShoulder, to: .leftBumper, from: controller)
		bindButton(gamepad.rightShoulder, to: .rightBumper, from: controller)

        // Triggers
		gamepad.leftTrigger.valueChangedHandler = { [weak self, weak controller] _, value, pressed in
			guard let self, let controller else { return }
			self.routeGameControllerTriggerInput(from: controller, value: value, pressed: pressed) { service, routedValue, routedPressed in
				service.updateLeftTrigger(routedValue, pressed: routedPressed)
			}
        }
		gamepad.rightTrigger.valueChangedHandler = { [weak self, weak controller] _, value, pressed in
			guard let self, let controller else { return }
			self.routeGameControllerTriggerInput(from: controller, value: value, pressed: pressed) { service, routedValue, routedPressed in
				service.updateRightTrigger(routedValue, pressed: routedPressed)
			}
        }

        // D-pad. Stickless clones (8BitDo Zero 2 impersonating a Pro Controller
        // in Switch mode, or a DualShock 4 in Mac mode) funnel the physical
        // d-pad through the left stick too, so once detected we suppress the
        // direct .dpad* mapping and let the stick mode govern it (Mouse default
        // / D-Pad option) — matching the Android-mode behavior. Genuine pads are
        // never detected as clones, so they bind normally. Routed through the
        // clone-aware handler only for the impersonated categories.
        let isCloneCapable = storage.lock.withLock { storage.isNintendo }
            || (gamepad as? GCDualShockGamepad) != nil
        if isCloneCapable {
            bindCloneAwareDpad(gamepad.dpad.up, to: .dpadUp, from: controller)
            bindCloneAwareDpad(gamepad.dpad.down, to: .dpadDown, from: controller)
            bindCloneAwareDpad(gamepad.dpad.left, to: .dpadLeft, from: controller)
            bindCloneAwareDpad(gamepad.dpad.right, to: .dpadRight, from: controller)
        } else {
            bindButton(gamepad.dpad.up, to: .dpadUp, from: controller)
            bindButton(gamepad.dpad.down, to: .dpadDown, from: controller)
            bindButton(gamepad.dpad.left, to: .dpadLeft, from: controller)
            bindButton(gamepad.dpad.right, to: .dpadRight, from: controller)
        }

        // Special buttons
		bindButton(gamepad.buttonMenu, to: .menu, from: controller)
		bindButton(gamepad.buttonOptions, to: .view, from: controller)
		if !isXboxElite {
			bindButton(gamepad.buttonHome, to: .xbox, from: controller)
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
				bindButton(captureButton, to: .share, from: controller)
                NSLog("[ControllerKeys] Nintendo capture button bound via physicalInputProfile (Button Share)")
            } else {
                // Fallback: scan for any unmapped button that might be the capture button
                let extendedKnown = knownNames.union([GCInputButtonHome])
                for (name, button) in controller.physicalInputProfile.buttons where !extendedKnown.contains(name) {
                    NSLog("[ControllerKeys] Nintendo unknown button found: %@", name)
					bindButton(button, to: .share, from: controller)
                    NSLog("[ControllerKeys] Nintendo capture button bound via unknown element: %@", name)
                    break
                }
            }
        }

		if let xboxGamepad {
            storage.lock.lock()
            storage.applyControllerTypeLocked(.xbox)
            storage.lock.unlock()
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)

            // Trigger battery monitor refresh for Xbox controller
            batteryMonitor.refreshBatteryLevel()

			bindButton(xboxGamepad.buttonShare, to: .share, from: controller)

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
                storage.applyControllerTypeLocked(.xboxElite)
				storage.elitePaddleEventSource = paddleEventSource
                storage.lock.unlock()
                UserDefaults.standard.set(true, forKey: Config.lastControllerWasXboxEliteKey)
                controllerName = "Xbox Elite Series 2 Controller"

                if hasPaddles {
					bindButton(xboxGamepad.paddleButton1, to: .xboxPaddle1, from: controller)
					bindButton(xboxGamepad.paddleButton2, to: .xboxPaddle2, from: controller)
					bindButton(xboxGamepad.paddleButton3, to: .xboxPaddle3, from: controller)
					bindButton(xboxGamepad.paddleButton4, to: .xboxPaddle4, from: controller)
                }

				// Launch helper process for Guide button and, when needed, paddle detection via raw HID.
                // gamecontrollerd blocks IOKit HID access to Elite 2 over BLE when
                // GameController.framework is loaded, so we use a separate process.
				startEliteHelper(paddleEventSource: paddleEventSource)
            } else {
                storage.lock.lock()
                storage.applyControllerTypeLocked(.xbox)
				storage.elitePaddleEventSource = .none
                storage.lock.unlock()
                UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
            }
        }

		bindButton(gamepad.leftThumbstickButton, to: .leftThumbstick, from: controller)
		bindButton(gamepad.rightThumbstickButton, to: .rightThumbstick, from: controller)

		gamepad.leftThumbstick.valueChangedHandler = { [weak self, weak controller] _, xValue, yValue in
			guard let self, let controller else { return }
			// Stickless Nintendo clones (e.g. 8BitDo Zero 2 in Switch mode)
			// funnel the d-pad through this phantom stick, and macOS
			// mis-calibrates its sign per connection. We drive the left stick
			// from the deterministic raw HID axes instead (see
			// handleNintendoHIDReport), so ignore the GameController value here.
			if self.threadSafeIsNintendoDPadStickClone { return }
			self.routeGameControllerStickInput(from: controller, x: xValue, y: yValue) { service, x, y in
				service.updateLeftStick(x: x, y: y)
			}
        }

		gamepad.rightThumbstick.valueChangedHandler = { [weak self, weak controller] _, xValue, yValue in
			guard let self, let controller else { return }
			self.routeGameControllerStickInput(from: controller, x: xValue, y: yValue) { service, x, y in
				service.updateRightStick(x: x, y: y)
			}
        }

        // DualSense-specific: Touchpad support
        if let dualSenseGamepad = gamepad as? GCDualSenseGamepad {
            storage.lock.lock()
            storage.applyControllerTypeLocked(.dualSense)
            storage.lock.unlock()
            UserDefaults.standard.set(true, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)

            setupTouchpadHandlers(
				for: controller,
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
            storage.applyControllerTypeLocked(.dualShock)
            storage.lock.unlock()
            UserDefaults.standard.set(true, forKey: Config.lastControllerWasDualShockKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
            UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)

            setupTouchpadHandlers(
				for: controller,
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
		storage.applyControllerTypeLocked(.appleTVRemote)
		storage.lock.unlock()

		UserDefaults.standard.set(true, forKey: Config.lastControllerWasAppleTVRemoteKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualSenseEdgeKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasDualShockKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasNintendoKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasXboxEliteKey)
		UserDefaults.standard.set(false, forKey: Config.lastControllerWasSteamControllerKey)

		controllerName = appleTVRemoteDisplayName(for: controller)

		// The remote's GATT battery service is readable, but its Bluetooth name
		// is a bare serial number, so the monitor needs the serial-name allowance
		// and a fresh connected-peripherals check (a connected remote never
		// advertises, so passive scanning would never find it).
		batteryMonitor.allowsSerialNamedPeripherals = true
		batteryMonitor.refreshBatteryLevel()

		microGamepad.allowsRotation = false
		microGamepad.reportsAbsoluteDpadValues = false

		bindButton(microGamepad.buttonA, to: .a, from: controller)
		bindButton(microGamepad.buttonX, to: .x, from: controller)
		bindButton(microGamepad.buttonMenu, to: .menu, from: controller)
		bindButton(microGamepad.dpad.up, to: .dpadUp, from: controller)
		bindButton(microGamepad.dpad.down, to: .dpadDown, from: controller)
		bindButton(microGamepad.dpad.left, to: .dpadLeft, from: controller)
		bindButton(microGamepad.dpad.right, to: .dpadRight, from: controller)

		microGamepad.dpad.valueChangedHandler = { [weak self, weak controller] _, xValue, yValue in
			guard let self, let controller else { return }
			self.routeGameControllerStickInput(from: controller, x: xValue, y: yValue) { service, x, y in
				service.updateLeftStick(x: x, y: y)
			}
		}

		bindAppleTVRemotePhysicalProfileButtons(controller.physicalInputProfile, from: controller)
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

    private func bindAppleTVRemotePhysicalProfileButtons(_ profile: GCPhysicalInputProfile, from controller: GCController) {
		var boundNames: [String] = []
		for (name, buttonInput) in profile.buttons {
			guard let controllerButton = appleTVRemoteButton(forPhysicalInputName: name) else {
				continue
			}
			bindButton(buttonInput, to: controllerButton, from: controller)
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
			releaseAppleTVRemoteButtonsIfNeeded()
			releaseAppleTVRemoteTouchIfStillActive()

				storage.lock.lock()
				storage.clearAppleTVRemoteFlagLocked()
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
        storage.applyControllerTypeLocked(.nintendo(ControllerJoyConSide(isLeft: isLeft, isRight: isRight)))
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
    private func setupPhysicalInputProfileHandlers(_ profile: GCPhysicalInputProfile, from controller: GCController) {
        // Diagnostic (CK_HID_DUMP=1): attach logging handlers to EVERY element
        // so we can see exactly what fires (incl. unmapped buttons like Star,
        // and whether the d-pad reports digital sub-buttons, an analog axis, or
        // both). Replaces normal binding while active.
        if Self.hidDumpEnabled {
            for (name, button) in profile.buttons {
                button.pressedChangedHandler = { _, _, pressed in
                    NSLog("[CK_HID_DUMP] BUTTON %@ = %d", name, pressed ? 1 : 0)
                }
            }
            for (name, dpad) in profile.dpads {
                dpad.valueChangedHandler = { _, x, y in
                    NSLog("[CK_HID_DUMP] DPAD %@ x=%.2f y=%.2f", name, x, y)
                }
            }
            NSLog("[CK_HID_DUMP] diagnostic handlers attached: buttons=%@ dpads=%@",
                  profile.buttons.keys.sorted().joined(separator: ", "),
                  profile.dpads.keys.sorted().joined(separator: ", "))
            return
        }

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

        // Stickless 8BitDo pads (Zero 2 / Micro in D-input mode) have no real
		// analog stick. When macOS exposes the physical d-pad as a
		// `Direction Pad`, bind it as real .dpad* buttons and do not also use it
		// as the left-stick fallback. The mapping canvas labels this control as
		// a D-pad, and Android-mode Micro reports digital D-pad directions here.
		let useDirectionPadAsLeftStickFallback = Self.shouldUsePhysicalDirectionPadAsLeftStickFallback(
			vendorName: controller.vendorName,
			productCategory: controller.productCategory
		)

        var boundCount = 0
        for (inputName, controllerButton) in buttonMap {
            if let element = profile.buttons[inputName] {
				bindButton(element, to: controllerButton, from: controller)
                boundCount += 1
            }
        }

		// D-pad.
		if let dpad = profile.dpads[GCInputDirectionPad] {
			bindButton(dpad.up, to: .dpadUp, from: controller)
			bindButton(dpad.down, to: .dpadDown, from: controller)
			bindButton(dpad.left, to: .dpadLeft, from: controller)
			bindButton(dpad.right, to: .dpadRight, from: controller)
            boundCount += 4
        }

        // Left thumbstick (analog) — use for mouse movement
        if let leftStick = profile.dpads[GCInputLeftThumbstick] {
			leftStick.valueChangedHandler = { [weak self, weak controller] _, xValue, yValue in
				guard let self, let controller else { return }
				self.routeGameControllerStickInput(from: controller, x: xValue, y: yValue) { service, x, y in
					service.updateLeftStick(x: x, y: y)
				}
            }
		} else if useDirectionPadAsLeftStickFallback, let dpad = profile.dpads[GCInputDirectionPad] {
            // Fallback: Joy-Con stick may be exposed as a D-pad rather than a thumbstick.
            // Use it for mouse movement so the user gets analog-like cursor control.
			dpad.valueChangedHandler = { [weak self, weak controller] _, xValue, yValue in
				guard let self, let controller else { return }
				self.routeGameControllerStickInput(from: controller, x: xValue, y: yValue) { service, x, y in
					service.updateLeftStick(x: x, y: y)
				}
            }
        }

        // Right thumbstick (analog)
        if let rightStick = profile.dpads[GCInputRightThumbstick] {
			rightStick.valueChangedHandler = { [weak self, weak controller] _, xValue, yValue in
				guard let self, let controller else { return }
				self.routeGameControllerStickInput(from: controller, x: xValue, y: yValue) { service, x, y in
					service.updateRightStick(x: x, y: y)
				}
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
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        storage.lock.lock()
        storage.leftStick = point
        let feedCloneDetector = storage.isDualShock
        storage.lock.unlock()

        // Feed the stickless-clone detector from the DualShock GameController
        // stick. (The Nintendo path feeds it from clean raw-HID axes instead —
        // see handleNintendoHIDReport — to avoid any GameController smoothing.)
        if feedCloneDetector {
            sticklessCloneDetector.noteLeftStick(point)
        }
    }

    nonisolated func updateRightStick(x: Float, y: Float) {
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        storage.lock.lock()
        storage.rightStick = point
        storage.lock.unlock()
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
            let uiButtons = storage.activeButtons
            storage.lock.unlock()

            Task { @MainActor in
                self.activeButtons = uiButtons
            }

            LatencyDiagnostics.mark("controller.lowLatencyPress \(button.rawValue)")
            emitInputEvent(.buttonPressed(button))
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
            storage.lock.unlock()
            emitInputEvent(.buttonReleased(button, holdDuration: holdDuration))
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
            emitInputEvent(.chordDetected(captured))
        } else if let button = captured.first {
            LatencyDiagnostics.mark("controller.delayedPress \(button.rawValue)")
            emitInputEvent(.buttonPressed(button))
        }

        for button in captured {
            if let duration = releases[button] {
                emitInputEvent(.buttonReleased(button, holdDuration: duration))
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
