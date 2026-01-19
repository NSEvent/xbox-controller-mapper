import Foundation

/// Global configuration constants for Xbox Controller Mapper
struct Config {

    // MARK: - Chord Detection
    /// Time window for detecting simultaneous button presses as a chord (seconds)
    static let chordDetectionWindow: TimeInterval = 0.15

    // MARK: - Long Hold Detection
    /// Default time threshold for distinguishing long hold from regular press (seconds)
    static let defaultLongHoldThreshold: TimeInterval = 0.5

    // MARK: - Double Tap Detection
    /// Default time window for double-tap detection (seconds)
    static let defaultDoubleTapThreshold: TimeInterval = 0.3

    // MARK: - Joystick Configuration
    /// Polling frequency for joystick input (Hz)
    static let joystickPollFrequency: Double = 120.0
    static let joystickPollInterval: TimeInterval = 1.0 / joystickPollFrequency

    /// Low-pass filter frequency range for joystick smoothing (Hz)
    static let joystickMinCutoffFrequency: Double = 4.0
    static let joystickMaxCutoffFrequency: Double = 14.0

    /// Joystick scrolling double-tap window (seconds)
    static let scrollDoubleTapWindow: TimeInterval = 0.4

    /// Threshold for scroll tap detection (0-1 range)
    static let scrollTapThreshold: Double = 0.45

    /// Direction ratio for scroll tap detection
    static let scrollTapDirectionRatio: Double = 0.8

    // MARK: - UI Display Updates
    /// Display refresh rate for UI updates (Hz, much slower than input processing)
    static let displayRefreshFrequency: Double = 15.0
    static let displayRefreshInterval: TimeInterval = 1.0 / displayRefreshFrequency

    /// Display update deadzone threshold - only update UI if value changes this much
    static let displayUpdateDeadzone: Double = 0.01

    /// Throttle display updates to avoid UI blocking with high-frequency joystick data
    static let displayUpdateThrottleMs: Int = Int(1000.0 / displayRefreshFrequency)

    // MARK: - Focus Mode
    /// Pause duration after exiting focus mode to allow joystick adjustment (seconds)
    static let focusExitPauseDuration: TimeInterval = 0.1

    /// Exponential smoothing constant for focus mode multiplier transitions
    static let focusMultiplierSmoothingAlpha: Double = 0.08

    /// Haptic feedback intensity for focus mode (0.0-1.0)
    static let focusEntryHapticIntensity: Float = 0.5
    static let focusEntryHapticSharpness: Float = 1.0
    static let focusEntryHapticDuration: TimeInterval = 0.12

    static let focusExitHapticIntensity: Float = 0.5
    static let focusExitHapticSharpness: Float = 0.3
    static let focusExitHapticDuration: TimeInterval = 0.15

    // MARK: - Input Simulation Timing
    /// Delay between modifier key presses (milliseconds)
    static let modifierPressDelay: useconds_t = 20000  // 20ms

    /// Delay before main key press after modifiers are held (milliseconds)
    static let postModifierDelay: useconds_t = 20000  // 20ms

    /// Duration to hold main key down (milliseconds)
    static let keyPressDuration: useconds_t = 50000  // 50ms

    /// Delay before releasing modifiers (milliseconds)
    static let preReleaseDelay: useconds_t = 20000  // 20ms

    // MARK: - Mouse Input
    /// Time threshold for distinguishing multi-clicks (seconds)
    static let multiClickThreshold: TimeInterval = 0.5

    // MARK: - DualSense Touchpad
    /// Sensitivity multiplier for touchpad mouse movement
    /// The touchpad reports normalized values (-1 to 1), so we scale up for usable mouse movement
    /// Higher values = faster/more sensitive touchpad
    static let touchpadSensitivityMultiplier: Double = 15.0
    /// Touchpad delta magnitude used to normalize acceleration curve
    static let touchpadAccelerationMaxDelta: Double = 0.12
    /// Maximum boost applied by touchpad acceleration
    static let touchpadAccelerationMaxBoost: Double = 2.0
    /// Minimum smoothing alpha to prevent freezing at max smoothing
    static let touchpadMinSmoothingAlpha: Double = 0.1
    /// Reset smoothing if touchpad events pause longer than this
    static let touchpadSmoothingResetInterval: TimeInterval = 0.12
    /// Movement threshold to ignore click-induced touchpad jitter
    static let touchpadClickMovementThreshold: Double = 0.015
    /// Time after touch starts before movement is allowed (prevents tap-induced drift)
    static let touchpadTouchSettleInterval: TimeInterval = 0.08
    /// Two-finger pan scaling (normalized delta -> pixel scroll)
    static let touchpadPanSensitivityMultiplier: Double = 500.0
    /// Minimum pan movement to start scrolling
    static let touchpadPanDeadzone: Double = 0.002
    /// Minimum distance between fingers to treat as two-finger gesture
    static let touchpadTwoFingerMinDistance: Double = 0.06
    /// How long to consider secondary touch valid without updates
    static let touchpadSecondaryStaleInterval: TimeInterval = 0.15
    /// Momentum tick frequency (Hz)
    static let touchpadMomentumFrequency: Double = 120.0
    /// Momentum tick interval (seconds)
    static let touchpadMomentumTickInterval: TimeInterval = 1.0 / touchpadMomentumFrequency
    /// Minimum time delta used for momentum calculations
    static let touchpadMomentumMinDeltaTime: TimeInterval = 1.0 / 240.0
    /// Max idle time before momentum is suppressed
    static let touchpadMomentumMaxIdleInterval: TimeInterval = 1.5
    /// Exponential decay rate for momentum velocity (per second)
    static let touchpadMomentumDecay: Double = 0.7
    /// Minimum velocity to start momentum after lift (pixels/second)
    static let touchpadMomentumStartVelocity: Double = 50.0
    /// Minimum velocity to keep momentum running (pixels/second)
    static let touchpadMomentumStopVelocity: Double = 30.0
    /// Maximum time since last fast pan sample to start momentum after lift (seconds)
    static let touchpadMomentumReleaseWindow: TimeInterval = 0.1
    /// Clamp momentum velocity to avoid spikes (pixels/second)
    static let touchpadMomentumMaxVelocity: Double = 20000.0
    /// Smoothing for gesture velocity estimation (0-1)
    static let touchpadMomentumVelocitySmoothingAlpha: Double = 0.35
    /// Boost applied to captured momentum velocity
    static let touchpadMomentumBoost: Double = 1.5
    /// UserDefaults key to enable touchpad debug logging
    static let touchpadDebugLoggingKey: String = "touchpad.debug"
    /// Env var to enable touchpad debug logging
    static let touchpadDebugEnvKey: String = "XCM_TOUCHPAD_DEBUG"
    /// Minimum interval between touchpad debug logs
    static let touchpadDebugLogInterval: TimeInterval = 0.05

    // MARK: - Button Processing
    /// Delay for chord button release processing (seconds)
    static let chordReleaseProcessingDelay: TimeInterval = 0.18

    /// Modifier key check delay (milliseconds)
    static let modifierReleaseCheckDelay: TimeInterval = 0.05

    // MARK: - Profile Management
    /// Default profile configuration directory
    static let configDirectory: String = {
        let homeDir = NSHomeDirectory()
        return (homeDir as NSString).appendingPathComponent(".xbox-controller-mapper")
    }()

    /// Configuration file name
    static let configFileName: String = "config.json"

    static var configFilePath: String {
        (configDirectory as NSString).appendingPathComponent(configFileName)
    }

    // MARK: - Battery Monitoring
    /// Interval between battery info updates (seconds)
    static let batteryUpdateInterval: TimeInterval = 10.0
}
