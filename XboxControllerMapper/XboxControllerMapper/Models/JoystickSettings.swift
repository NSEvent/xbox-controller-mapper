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

    /// Deadzone for touchpad movement (0.0 - 0.005)
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

    static let `default` = JoystickSettings()

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
               (0.0...0.005).contains(touchpadDeadzone) &&
               range.contains(touchpadSmoothing) &&
               range.contains(touchpadPanSensitivity) &&
               (0.5...5.0).contains(touchpadZoomToPanRatio) &&
               range.contains(scrollAcceleration) &&
               (1.0...4.0).contains(scrollBoostMultiplier) &&
               range.contains(focusModeSensitivity)
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mouseSensitivity = try container.decodeIfPresent(Double.self, forKey: .mouseSensitivity) ?? 0.5
        scrollSensitivity = try container.decodeIfPresent(Double.self, forKey: .scrollSensitivity) ?? 0.5
        mouseDeadzone = try container.decodeIfPresent(Double.self, forKey: .mouseDeadzone) ?? 0.15
        scrollDeadzone = try container.decodeIfPresent(Double.self, forKey: .scrollDeadzone) ?? 0.15
        invertMouseY = try container.decodeIfPresent(Bool.self, forKey: .invertMouseY) ?? false
        invertScrollY = try container.decodeIfPresent(Bool.self, forKey: .invertScrollY) ?? false
        mouseAcceleration = try container.decodeIfPresent(Double.self, forKey: .mouseAcceleration) ?? 0.5
        touchpadSensitivity = try container.decodeIfPresent(Double.self, forKey: .touchpadSensitivity) ?? 0.5
        touchpadAcceleration = try container.decodeIfPresent(Double.self, forKey: .touchpadAcceleration) ?? 0.5
        touchpadDeadzone = try container.decodeIfPresent(Double.self, forKey: .touchpadDeadzone) ?? 0.001
        touchpadSmoothing = try container.decodeIfPresent(Double.self, forKey: .touchpadSmoothing) ?? 0.4
        touchpadPanSensitivity = try container.decodeIfPresent(Double.self, forKey: .touchpadPanSensitivity) ?? 0.5
        touchpadZoomToPanRatio = try container.decodeIfPresent(Double.self, forKey: .touchpadZoomToPanRatio) ?? 1.95
        touchpadUseNativeZoom = try container.decodeIfPresent(Bool.self, forKey: .touchpadUseNativeZoom) ?? true
        scrollAcceleration = try container.decodeIfPresent(Double.self, forKey: .scrollAcceleration) ?? 0.5
        scrollBoostMultiplier = try container.decodeIfPresent(Double.self, forKey: .scrollBoostMultiplier) ?? 2.0
        focusModeSensitivity = try container.decodeIfPresent(Double.self, forKey: .focusModeSensitivity) ?? 0.2
        focusModeModifier = try container.decodeIfPresent(ModifierFlags.self, forKey: .focusModeModifier) ?? .command
        leftStickMode = try container.decodeIfPresent(StickMode.self, forKey: .leftStickMode) ?? .mouse
        rightStickMode = try container.decodeIfPresent(StickMode.self, forKey: .rightStickMode) ?? .scroll
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
    }
}
