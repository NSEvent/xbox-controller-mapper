import Foundation

/// Global configuration constants for ControllerKeys
struct Config {

    // MARK: - Chord Detection
    /// Time window for detecting simultaneous button presses as a chord (seconds)
    static let chordDetectionWindow: TimeInterval = 0.15

    // MARK: - Sequence Detection
    /// Default max time between consecutive button presses in a sequence (seconds)
    static let defaultSequenceStepTimeout: TimeInterval = 0.4
    /// Maximum steps allowed in a sequence
    static let maxSequenceSteps: Int = 8

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

    /// Horizontal scroll threshold ratio - prevents accidental panning when scrolling vertically
    /// When |y| > |x| (vertical dominant), horizontal scroll is suppressed unless |x| >= |y| * ratio
    /// Higher values = harder to accidentally pan (0.5 means horizontal must be 50% of vertical)
    static let scrollHorizontalThresholdRatio: Double = 0.7

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

    /// Haptic feedback for command wheel segment changes (crisp light tick)
    static let wheelSegmentHapticIntensity: Float = 0.12
    static let wheelSegmentHapticSharpness: Float = 1.0

    /// Haptic feedback for crossing the command wheel perimeter boundary (deep thud)
    static let wheelPerimeterHapticIntensity: Float = 0.35
    static let wheelPerimeterHapticSharpness: Float = 0.15

    /// Haptic feedback for force quit ready (light double-tap confirmation)
    static let wheelForceQuitHapticIntensity: Float = 0.15
    static let wheelForceQuitHapticSharpness: Float = 1.0
    static let wheelForceQuitHapticGap: TimeInterval = 0.05
    /// Haptic feedback for command wheel activation (selection confirmed)
    static let wheelActivateHapticIntensity: Float = 0.18
    static let wheelActivateHapticSharpness: Float = 0.7
    static let wheelActivateHapticDuration: TimeInterval = 0.08
    /// Haptic feedback for command wheel secondary action (force quit / incognito)
    static let wheelSecondaryHapticIntensity: Float = 0.3
    static let wheelSecondaryHapticSharpness: Float = 0.9
    static let wheelSecondaryHapticDuration: TimeInterval = 0.1
    /// Haptic feedback for switching command wheel item sets (primary/secondary)
    static let wheelSetEnterHapticIntensity: Float = 0.22
    static let wheelSetEnterHapticSharpness: Float = 0.9
    static let wheelSetEnterHapticDuration: TimeInterval = 0.06
    static let wheelSetExitHapticIntensity: Float = 0.16
    static let wheelSetExitHapticSharpness: Float = 0.4
    static let wheelSetExitHapticDuration: TimeInterval = 0.07
    /// Minimum time between command wheel haptic ticks
    static let wheelSegmentHapticCooldown: TimeInterval = 0.06
    static let wheelPerimeterHapticCooldown: TimeInterval = 0.08

    /// Haptic feedback for on-screen keyboard visibility
    static let keyboardShowHapticIntensity: Float = 0.2
    static let keyboardShowHapticSharpness: Float = 0.6
    static let keyboardShowHapticDuration: TimeInterval = 0.08
    static let keyboardHideHapticIntensity: Float = 0.15
    static let keyboardHideHapticSharpness: Float = 0.3
    static let keyboardHideHapticDuration: TimeInterval = 0.08
    /// Haptic feedback for on-screen keyboard actions (key/app/quick text)
    static let keyboardActionHapticIntensity: Float = 0.12
    static let keyboardActionHapticSharpness: Float = 0.8
    static let keyboardActionHapticDuration: TimeInterval = 0.06

    /// Haptic feedback for webhook/HTTP request success (crisp confirmation)
    static let webhookSuccessHapticIntensity: Float = 0.25
    static let webhookSuccessHapticSharpness: Float = 0.9
    static let webhookSuccessHapticDuration: TimeInterval = 0.08

    /// Haptic feedback for webhook/HTTP request failure (double pulse, more intense)
    static let webhookFailureHapticIntensity: Float = 0.5
    static let webhookFailureHapticSharpness: Float = 0.3
    static let webhookFailureHapticDuration: TimeInterval = 0.15
    static let webhookFailureHapticGap: TimeInterval = 0.1  // Gap between double pulses

    // MARK: - Input Simulation Timing
    /// Delay between modifier key presses (milliseconds)
    static let modifierPressDelay: useconds_t = 20000  // 20ms

    /// Delay before main key press after modifiers are held (milliseconds)
    static let postModifierDelay: useconds_t = 20000  // 20ms

    /// Duration to hold main key down (milliseconds)
    static let keyPressDuration: useconds_t = 50000  // 50ms

    /// Delay before releasing modifiers (milliseconds)
    static let preReleaseDelay: useconds_t = 20000  // 20ms
    
    /// Delay between keystrokes when typing text (milliseconds)
    static let typingDelay: useconds_t = 10000  // 10ms

    // MARK: - Mouse Input
    /// Time threshold for distinguishing multi-clicks (seconds)
    static let multiClickThreshold: TimeInterval = 0.5
    /// Max age for tracked controller cursor position to be used for click placement under Accessibility Zoom
    static let zoomTrackedClickMaxAge: TimeInterval = 2.0

    // MARK: - DualSense Touchpad
    /// Base scale for converting touchpad normalized deltas to mouse counts.
    /// DualSense touchpad is ~41mm wide, normalized to -1..1 (2.0 range).
    /// This converts to mouse counts that macOS native acceleration can work with.
    /// Value tuned so that default sensitivity feels like a regular Mac trackpad.
    static let touchpadNativeScale: Double = 650.0
    /// Legacy sensitivity multiplier (kept for non-native code paths)
    static let touchpadSensitivityMultiplier: Double = 15.0
    /// Touchpad delta magnitude used to normalize acceleration curve
    static let touchpadAccelerationMaxDelta: Double = 0.12
    /// Maximum boost applied by touchpad acceleration
    static let touchpadAccelerationMaxBoost: Double = 2.0
    /// Minimum smoothing alpha to prevent freezing at max smoothing
    static let touchpadMinSmoothingAlpha: Double = 0.1
    /// Reset smoothing if touchpad events pause longer than this
    static let touchpadSmoothingResetInterval: TimeInterval = 0.12
    /// Movement threshold to ignore click-induced touchpad jitter and tap drift
    /// DualSense touchpad has inherent drift of ~0.02-0.03 even when holding still
    static let touchpadClickMovementThreshold: Double = 0.04
    /// Time after touch starts before movement is allowed (prevents tap-induced drift)
    /// Increased to 150ms to cover most tap durations
    static let touchpadTouchSettleInterval: TimeInterval = 0.15
    /// Maximum duration for a touch to be recognized as a tap (for tap-to-click gesture)
    static let touchpadTapMaxDuration: TimeInterval = 0.5
    /// Maximum movement during a tap for it to still be recognized as a tap
    /// DualSense touchpad has significant inherent jitter, so this needs to be fairly high
    static let touchpadTapMaxMovement: Double = 0.35
    /// Duration for a touch to trigger long tap (uses same threshold as button long hold)
    static let touchpadLongTapThreshold: TimeInterval = 0.5
    /// Maximum movement during a long tap (tighter than regular tap since user is holding still)
    static let touchpadLongTapMaxMovement: Double = 0.05
    /// Maximum movement for secondary finger in two-finger tap (more lenient due to touchpad noise)
    /// DualSense secondary finger tracking is very noisy, needs high threshold
    static let touchpadTwoFingerTapMaxMovement: Double = 0.9
    /// Maximum cumulative gesture (center) movement for two-finger tap
    /// If the gesture center moved more than this, it's a scroll/pan, not a tap
    static let touchpadTwoFingerTapMaxGestureDistance: Double = 0.05
    /// Maximum cumulative pinch (finger distance change) for two-finger tap
    /// If fingers moved apart/together more than this, it's a pinch/zoom, not a tap
    static let touchpadTwoFingerTapMaxPinchDistance: Double = 0.05
    /// Minimum pinch (distance change) to trigger zoom gesture
    /// Higher = requires more deliberate pinch to trigger zoom
    static let touchpadPinchDeadzone: Double = 0.05
    /// Brief lock to prevent pinch direction flips on quick releases (prevents snap-back)
    static let touchpadPinchDirectionLockInterval: TimeInterval = 0.1
    /// Sensitivity multiplier for pinch-to-zoom (distance delta -> scroll amount)
    static let touchpadPinchSensitivityMultiplier: Double = 12000.0
    /// Ratio threshold: if pinch/pan ratio exceeds this, treat as pinch gesture
    /// Higher = pinch must be more dominant over pan to trigger zoom
    static let touchpadPinchVsPanRatio: Double = 1.8
    /// Cooldown period after a tap where movement is suppressed (prevents double-tap drift)
    static let touchpadTapCooldown: TimeInterval = 0.2
    /// Two-finger pan scaling (normalized delta -> pixel scroll)
    static let touchpadPanSensitivityMultiplier: Double = 3000.0
    /// Minimum pan movement to start scrolling
    static let touchpadPanDeadzone: Double = 0.002
    /// Minimum distance between fingers to treat as two-finger gesture
    static let touchpadTwoFingerMinDistance: Double = 0.06
    /// How long to consider secondary touch valid without updates (also blocks mouse movement after gestures)
    static let touchpadSecondaryStaleInterval: TimeInterval = 0.04
    /// Momentum tick frequency (Hz)
    static let touchpadMomentumFrequency: Double = 120.0
    /// Momentum tick interval (seconds)
    static let touchpadMomentumTickInterval: TimeInterval = 1.0 / touchpadMomentumFrequency
    /// Minimum time delta used for momentum calculations
    static let touchpadMomentumMinDeltaTime: TimeInterval = 1.0 / 240.0
    /// Max idle time before momentum is suppressed
    static let touchpadMomentumMaxIdleInterval: TimeInterval = 1.5
    /// Exponential decay rate for momentum velocity (per second)
    static let touchpadMomentumDecay: Double = 0.95
    /// Minimum velocity to start momentum after lift (pixels/second)
    static let touchpadMomentumStartVelocity: Double = 1100.0
    /// Minimum duration velocity must exceed threshold before momentum is triggered (seconds)
    static let touchpadMomentumSustainedDuration: TimeInterval = 0.03
    /// Minimum velocity to keep momentum running (pixels/second)
    static let touchpadMomentumStopVelocity: Double = 30.0
    /// Maximum time since last fast pan sample to start momentum after lift (seconds)
    static let touchpadMomentumReleaseWindow: TimeInterval = 0.1
    /// Clamp momentum velocity to avoid spikes (pixels/second)
    static let touchpadMomentumMaxVelocity: Double = 20000.0
    /// Smoothing for gesture velocity estimation (0-1)
    static let touchpadMomentumVelocitySmoothingAlpha: Double = 0.35
    /// Minimum boost applied at threshold velocity
    static let touchpadMomentumBoostMin: Double = 0.4
    /// Maximum boost applied at high velocities
    static let touchpadMomentumBoostMax: Double = 1.4
    /// Velocity at which max boost is reached (pixels/second)
    static let touchpadMomentumBoostMaxVelocity: Double = 5000.0
    /// UserDefaults key for remembering last connected controller type (DualSense/PS5)
    static let lastControllerWasDualSenseKey: String = "lastControllerWasDualSense"
    /// UserDefaults key for remembering if last DualSense was an Edge controller
    static let lastControllerWasDualSenseEdgeKey: String = "lastControllerWasDualSenseEdge"
    /// UserDefaults key for remembering last connected controller type (DualShock/PS4)
    static let lastControllerWasDualShockKey: String = "lastControllerWasDualShock"
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
    /// New configuration directory (preferred)
    static let configDirectory: String = {
        let homeDir = NSHomeDirectory()
        return (homeDir as NSString).appendingPathComponent(".controllerkeys")
    }()

    /// Legacy configuration directory (for migration)
    static let legacyConfigDirectory: String = {
        let homeDir = NSHomeDirectory()
        return (homeDir as NSString).appendingPathComponent(".xbox-controller-mapper")
    }()

    /// Configuration file name
    static let configFileName: String = "config.json"

    static var configFilePath: String {
        (configDirectory as NSString).appendingPathComponent(configFileName)
    }

    static var legacyConfigFilePath: String {
        (legacyConfigDirectory as NSString).appendingPathComponent(configFileName)
    }

    // MARK: - Scripting
    /// Maximum execution time for a single script invocation (milliseconds)
    static let scriptExecutionTimeoutMs: Int = 500
    /// Maximum execution time for shell() commands within scripts (seconds)
    static let shellCommandTimeoutSeconds: Int = 5

    // MARK: - Swipe Typing
    /// Left trigger threshold to begin a swipe gesture
    static let swipeTriggerThreshold: Float = 0.5
    /// Left trigger threshold to end a swipe gesture (hysteresis)
    static let swipeTriggerReleaseThreshold: Float = 0.4
    /// Minimum samples required before running inference
    static let swipeMinimumSamples: Int = 5
    /// Maximum samples collected per swipe gesture
    static let swipeMaximumSamples: Int = 256
    /// Maximum sample rate for swipe path collection (Hz)
    static let swipeSampleRateLimit: Double = 60.0

    // MARK: - Battery Monitoring
    /// Interval between battery info updates (seconds)
    static let batteryUpdateInterval: TimeInterval = 10.0
}

// MARK: - Button Colors

import SwiftUI

/// Centralized color definitions for controller face buttons
enum ButtonColors {
    // MARK: - Xbox Face Button Colors
    static let xboxA = Color(red: 0.4, green: 0.8, blue: 0.2)   // Vibrant Green
    static let xboxB = Color(red: 0.9, green: 0.2, blue: 0.2)   // Jewel Red
    static let xboxX = Color(red: 0.1, green: 0.4, blue: 0.9)   // Deep Blue
    static let xboxY = Color(red: 1.0, green: 0.7, blue: 0.0)   // Amber/Gold

    // MARK: - PlayStation Face Button Colors
    static let psCross = Color(red: 0.55, green: 0.70, blue: 0.95)    // Light Blue
    static let psCircle = Color(red: 1.0, green: 0.45, blue: 0.50)    // Red/Pink
    static let psSquare = Color(red: 0.90, green: 0.55, blue: 0.75)   // Pink/Magenta
    static let psTriangle = Color(red: 0.45, green: 0.85, blue: 0.75) // Teal/Cyan

    /// Get Xbox face button color for a button
    static func xbox(_ button: ControllerButton) -> Color? {
        switch button {
        case .a: return xboxA
        case .b: return xboxB
        case .x: return xboxX
        case .y: return xboxY
        default: return nil
        }
    }

    /// Get PlayStation face button color for a button
    static func playStation(_ button: ControllerButton) -> Color? {
        switch button {
        case .a: return psCross     // Cross
        case .b: return psCircle    // Circle
        case .x: return psSquare    // Square
        case .y: return psTriangle  // Triangle
        default: return nil
        }
    }
}
