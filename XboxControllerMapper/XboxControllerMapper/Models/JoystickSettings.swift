import Foundation

/// Mode for each analog stick
enum StickMode: String, Codable, CaseIterable {
    case none = "none"
    case mouse = "mouse"
    case scroll = "scroll"
    case wasdKeys = "wasdKeys"
    case arrowKeys = "arrowKeys"

    var displayName: String {
        switch self {
        case .none: return "None"
        case .mouse: return "Mouse"
        case .scroll: return "Scroll"
        case .wasdKeys: return "WASD"
        case .arrowKeys: return "Arrows"
        }
    }
}

/// Settings for joystick behavior
struct JoystickSettings: Codable, Equatable {
    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// Mouse movement sensitivity (0.0 - 1.0, where 0.5 is default)
    var mouseSensitivity: Double = 0.5

    /// Scroll speed sensitivity (0.0 - 1.0, where 0.5 is default)
    var scrollSensitivity: Double = 0.5

    /// Deadzone for mouse movement (0.0 - 1.0)
    var mouseDeadzone: Double = 0.15

    /// Deadzone for scrolling (0.0 - 1.0)
    var scrollDeadzone: Double = 0.15

    /// Invert vertical mouse movement
    var invertMouseY: Bool = false

    /// Invert vertical scroll direction
    var invertScrollY: Bool = false

    /// Acceleration curve for mouse movement (0.0 = linear, 1.0 = max acceleration)
    var mouseAcceleration: Double = 0.5

    /// Touchpad sensitivity (0.0 - 1.0)
    var touchpadSensitivity: Double = 0.5

    /// Touchpad acceleration curve (0.0 = linear, 1.0 = max acceleration)
    var touchpadAcceleration: Double = 0.5

    /// Deadzone for touchpad movement (0.0 - 0.01)
    var touchpadDeadzone: Double = 0.001

    /// Smoothing amount for touchpad movement (0.0 - 1.0)
    var touchpadSmoothing: Double = 0.4

    /// Two-finger pan sensitivity (0.0 - 1.0)
    var touchpadPanSensitivity: Double = 0.5

    /// Pan to zoom ratio threshold (low = easier to zoom, high = easier to pan)
    var touchpadZoomToPanRatio: Double = 1.95

    /// Whether to use native magnify gestures (true) or Cmd+Plus/Minus (false) for zoom
    var touchpadUseNativeZoom: Bool = true

    /// Acceleration curve for scrolling (0.0 = linear, 1.0 = max acceleration)
    var scrollAcceleration: Double = 0.5

    /// Multiplier applied to scroll speed after a double-tap up/down
    var scrollBoostMultiplier: Double = 2.0

    /// Sensitivity to use when focus modifier is held (0.0 - 1.0)
    var focusModeSensitivity: Double = 0.1

    /// Modifier that triggers focus mode (slower mouse speed)
    var focusModeModifier: ModifierFlags = .command

    /// Mode for left stick (default: mouse)
    var leftStickMode: StickMode = .mouse

    /// Mode for right stick (default: scroll)
    var rightStickMode: StickMode = .scroll

    /// Whether gyroscope aiming is enabled during focus mode (DualSense only)
    var gyroAimingEnabled: Bool = false

    /// Sensitivity for gyroscope aiming (0.0 - 1.0)
    var gyroAimingSensitivity: Double = 0.3

    /// Deadzone for gyroscope aiming (0.0 - 1.0, rad/s threshold)
    var gyroAimingDeadzone: Double = 0.3

    /// Motion gesture sensitivity (0.0 = hard to trigger, 1.0 = very sensitive)
    var gestureSensitivity: Double = 0.5

    /// Motion gesture cooldown (0.0 = fast repeat, 1.0 = slow repeat)
    var gestureCooldown: Double = 0.5

    static let `default` = JoystickSettings()

    /// Converts 0-1 gyro aiming sensitivity to pixel-scale multiplier (cubic curve)
    var gyroAimingMultiplier: Double {
        return 1.0 + pow(gyroAimingSensitivity, 3.0) * 20.0
    }

    // MARK: - Gesture Detection Computed Properties

    /// Pitch activation threshold (rad/s): 0.0→7.0 (hard), 0.5→5.0 (default), 1.0→3.0 (sensitive)
    var effectiveGestureActivationThreshold: Double {
        7.0 - gestureSensitivity * 4.0
    }

    /// Pitch minimum peak velocity (rad/s): 0.0→9.0, 0.5→7.0, 1.0→5.0
    var effectiveGestureMinPeakVelocity: Double {
        9.0 - gestureSensitivity * 4.0
    }

    /// Roll activation threshold (proportional to pitch: pitch * 0.7)
    var effectiveGestureRollActivationThreshold: Double {
        effectiveGestureActivationThreshold * 0.7
    }

    /// Roll minimum peak velocity (proportional to pitch: pitch * 5/7)
    var effectiveGestureRollMinPeakVelocity: Double {
        effectiveGestureMinPeakVelocity * (5.0 / 7.0)
    }

    /// Same-direction cooldown (seconds): 0.0→0.2s, 0.5→0.5s, 1.0→1.0s
    var effectiveGestureCooldown: TimeInterval {
        0.4 * gestureCooldown * gestureCooldown + 0.4 * gestureCooldown + 0.2
    }

    /// Opposite-direction cooldown (always 3x same-direction)
    var effectiveGestureOppositeDirectionCooldown: TimeInterval {
        effectiveGestureCooldown * 3.0
    }

    /// Validates settings ranges
    func isValid() -> Bool {
        let range = 0.0...1.0
        return range.contains(mouseSensitivity) &&
               range.contains(scrollSensitivity) &&
               range.contains(mouseDeadzone) &&
               range.contains(scrollDeadzone) &&
               range.contains(mouseAcceleration) &&
               range.contains(touchpadSensitivity) &&
               range.contains(touchpadAcceleration) &&
               (0.0...0.01).contains(touchpadDeadzone) &&
               range.contains(touchpadSmoothing) &&
               range.contains(touchpadPanSensitivity) &&
               (0.5...5.0).contains(touchpadZoomToPanRatio) &&
               range.contains(scrollAcceleration) &&
               (1.0...4.0).contains(scrollBoostMultiplier) &&
               range.contains(focusModeSensitivity) &&
               range.contains(gyroAimingSensitivity) &&
               range.contains(gyroAimingDeadzone) &&
               range.contains(gestureSensitivity) &&
               range.contains(gestureCooldown)
    }

    /// Converts 0-1 sensitivity to actual multiplier for mouse
    var mouseMultiplier: Double {
        return calculateMouseMultiplier(sensitivity: mouseSensitivity)
    }

    /// Converts 0-1 focus sensitivity to actual multiplier for mouse
    var focusMultiplier: Double {
        return calculateMouseMultiplier(sensitivity: focusModeSensitivity)
    }
    
    private func calculateMouseMultiplier(sensitivity: Double) -> Double {
        // Map 0-1 to 2-120 range (exponential for better feel)
        return 2.0 + pow(sensitivity, 3.0) * 118.0
    }

    private func calibratedTouchpadValue(_ raw: Double, boost: Double) -> Double {
        // Calibration curve: keeps 0 and 1 stable, but maps 0.5 -> 0.5 + boost * 0.25.
        return min(1.0, max(0.0, raw + boost * raw * (1.0 - raw)))
    }

    /// Touchpad sensitivity after calibration (0.5 UI -> ~0.8 effective)
    var effectiveTouchpadSensitivity: Double {
        calibratedTouchpadValue(touchpadSensitivity, boost: 1.2)
    }

    /// Touchpad acceleration after calibration (0.5 UI -> ~0.9 effective)
    var effectiveTouchpadAcceleration: Double {
        calibratedTouchpadValue(touchpadAcceleration, boost: 1.6)
    }

    /// Converts 0-1 sensitivity to touchpad multiplier (0.25 - 1.75)
    var touchpadSensitivityMultiplier: Double {
        return 0.25 + effectiveTouchpadSensitivity * 1.5
    }

    /// Converts 0-1 sensitivity to actual multiplier for scroll
    var scrollMultiplier: Double {
        // Map 0-1 to 1-30 range
        return 1.0 + pow(scrollSensitivity, 1.5) * 29.0
    }

    /// Converts 0-1 acceleration to exponent value
    var mouseAccelerationExponent: Double {
        // Map 0-1 to 1.0-3.0 (1.0 = linear, higher = more acceleration)
        return 1.0 + mouseAcceleration * 2.0
    }

    /// Converts 0-1 acceleration to exponent value
    var touchpadAccelerationExponent: Double {
        // Map 0-1 to 1.0-3.0 (1.0 = linear, higher = more acceleration)
        return 1.0 + effectiveTouchpadAcceleration * 2.0
    }

    /// Converts 0-1 acceleration to exponent value
    var scrollAccelerationExponent: Double {
        // Map 0-1 to 1.0-2.5
        return 1.0 + scrollAcceleration * 1.5
    }
}

// MARK: - Custom Codable (handles new fields with defaults)

extension JoystickSettings {
    enum CodingKeys: String, CodingKey {
        case mouseSensitivity
        case scrollSensitivity
        case mouseDeadzone
        case scrollDeadzone
        case invertMouseY
        case invertScrollY
        case mouseAcceleration
        case touchpadSensitivity
        case touchpadAcceleration
        case touchpadDeadzone
        case touchpadSmoothing
        case touchpadPanSensitivity
        case touchpadZoomToPanRatio
        case touchpadUseNativeZoom
        case scrollAcceleration
        case scrollBoostMultiplier
        case focusModeSensitivity
        case focusModeModifier
        case leftStickMode
        case rightStickMode
        case gyroAimingEnabled
        case gyroAimingSensitivity
        case gyroAimingDeadzone
        case gestureSensitivity
        case gestureCooldown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mouseSensitivity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .mouseSensitivity) ?? 0.5,
            to: 0.0...1.0,
            fallback: 0.5
        )
        scrollSensitivity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? 0.5,
            to: 0.0...1.0,
            fallback: 0.5
        )
        mouseDeadzone = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .mouseDeadzone) ?? 0.15,
            to: 0.0...1.0,
            fallback: 0.15
        )
        scrollDeadzone = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .scrollDeadzone) ?? 0.15,
            to: 0.0...1.0,
            fallback: 0.15
        )
        invertMouseY = try container.decodeIfPresent(Bool.self, forKey: .invertMouseY) ?? false
        invertScrollY = try container.decodeIfPresent(Bool.self, forKey: .invertScrollY) ?? false
        mouseAcceleration = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .mouseAcceleration) ?? 0.5,
            to: 0.0...1.0,
            fallback: 0.5
        )
        touchpadSensitivity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .touchpadSensitivity) ?? 0.5,
            to: 0.0...1.0,
            fallback: 0.5
        )
        touchpadAcceleration = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .touchpadAcceleration) ?? 0.5,
            to: 0.0...1.0,
            fallback: 0.5
        )
        touchpadDeadzone = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .touchpadDeadzone) ?? 0.001,
            to: 0.0...0.01,
            fallback: 0.001
        )
        touchpadSmoothing = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .touchpadSmoothing) ?? 0.4,
            to: 0.0...1.0,
            fallback: 0.4
        )
        touchpadPanSensitivity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .touchpadPanSensitivity) ?? 0.5,
            to: 0.0...1.0,
            fallback: 0.5
        )
        touchpadZoomToPanRatio = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .touchpadZoomToPanRatio) ?? 1.95,
            to: 0.5...5.0,
            fallback: 1.95
        )
        touchpadUseNativeZoom = try container.decodeIfPresent(Bool.self, forKey: .touchpadUseNativeZoom) ?? true
        scrollAcceleration = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .scrollAcceleration) ?? 0.5,
            to: 0.0...1.0,
            fallback: 0.5
        )
        scrollBoostMultiplier = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .scrollBoostMultiplier) ?? 2.0,
            to: 1.0...4.0,
            fallback: 2.0
        )
        focusModeSensitivity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .focusModeSensitivity) ?? 0.2,
            to: 0.0...1.0,
            fallback: 0.2
        )
        focusModeModifier = try container.decodeIfPresent(ModifierFlags.self, forKey: .focusModeModifier) ?? .command
        leftStickMode = try container.decodeIfPresent(StickMode.self, forKey: .leftStickMode) ?? .mouse
        rightStickMode = try container.decodeIfPresent(StickMode.self, forKey: .rightStickMode) ?? .scroll
        gyroAimingEnabled = try container.decodeIfPresent(Bool.self, forKey: .gyroAimingEnabled) ?? false
        gyroAimingSensitivity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .gyroAimingSensitivity) ?? 0.3,
            to: 0.0...1.0,
            fallback: 0.3
        )
        gyroAimingDeadzone = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .gyroAimingDeadzone) ?? 0.3,
            to: 0.0...1.0,
            fallback: 0.3
        )
        gestureSensitivity = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .gestureSensitivity) ?? 0.5,
            to: 0.0...1.0,
            fallback: 0.5
        )
        gestureCooldown = Self.clamp(
            try container.decodeIfPresent(Double.self, forKey: .gestureCooldown) ?? 0.5,
            to: 0.0...1.0,
            fallback: 0.5
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mouseSensitivity, forKey: .mouseSensitivity)
        try container.encode(scrollSensitivity, forKey: .scrollSensitivity)
        try container.encode(mouseDeadzone, forKey: .mouseDeadzone)
        try container.encode(scrollDeadzone, forKey: .scrollDeadzone)
        try container.encode(invertMouseY, forKey: .invertMouseY)
        try container.encode(invertScrollY, forKey: .invertScrollY)
        try container.encode(mouseAcceleration, forKey: .mouseAcceleration)
        try container.encode(touchpadSensitivity, forKey: .touchpadSensitivity)
        try container.encode(touchpadAcceleration, forKey: .touchpadAcceleration)
        try container.encode(touchpadDeadzone, forKey: .touchpadDeadzone)
        try container.encode(touchpadSmoothing, forKey: .touchpadSmoothing)
        try container.encode(touchpadPanSensitivity, forKey: .touchpadPanSensitivity)
        try container.encode(touchpadZoomToPanRatio, forKey: .touchpadZoomToPanRatio)
        try container.encode(touchpadUseNativeZoom, forKey: .touchpadUseNativeZoom)
        try container.encode(scrollAcceleration, forKey: .scrollAcceleration)
        try container.encode(scrollBoostMultiplier, forKey: .scrollBoostMultiplier)
        try container.encode(focusModeSensitivity, forKey: .focusModeSensitivity)
        try container.encode(focusModeModifier, forKey: .focusModeModifier)
        try container.encode(leftStickMode, forKey: .leftStickMode)
        try container.encode(rightStickMode, forKey: .rightStickMode)
        try container.encode(gyroAimingEnabled, forKey: .gyroAimingEnabled)
        try container.encode(gyroAimingSensitivity, forKey: .gyroAimingSensitivity)
        try container.encode(gyroAimingDeadzone, forKey: .gyroAimingDeadzone)
        try container.encode(gestureSensitivity, forKey: .gestureSensitivity)
        try container.encode(gestureCooldown, forKey: .gestureCooldown)
    }
}
