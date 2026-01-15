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

    // MARK: - Button Processing
    /// Delay for chord button release processing (seconds)
    static let chordReleaseProcessingDelay: TimeInterval = 0.18

    /// Modifier key check delay (milliseconds)
    static let modifierReleaseCheckDelay: TimeInterval = 0.05

    // MARK: - Profile Management
    /// Default profile configuration directory
    static let configDirectory: String = {
        let homeDir = NSHomeDirectory()
        return (homeDir as NSString).appendingPathComponent(".xcontrollermapper")
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
