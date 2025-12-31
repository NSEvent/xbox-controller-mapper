import Foundation

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

    /// Acceleration curve for scrolling (0.0 = linear, 1.0 = max acceleration)
    var scrollAcceleration: Double = 0.5

    /// Multiplier applied to scroll speed after a double-tap up/down
    var scrollBoostMultiplier: Double = 2.0

    static let `default` = JoystickSettings()

    /// Validates settings ranges
    func isValid() -> Bool {
        let range = 0.0...1.0
        return range.contains(mouseSensitivity) &&
               range.contains(scrollSensitivity) &&
               range.contains(mouseDeadzone) &&
               range.contains(scrollDeadzone) &&
               range.contains(mouseAcceleration) &&
               range.contains(scrollAcceleration) &&
               (1.0...4.0).contains(scrollBoostMultiplier)
    }

    /// Converts 0-1 sensitivity to actual multiplier for mouse
    var mouseMultiplier: Double {
        // Map 0-1 to 2-60 range (exponential for better feel)
        // Increased max for faster mouse movement at high sensitivity
        return 2.0 + pow(mouseSensitivity, 1.5) * 58.0
    }

    /// Converts 0-1 sensitivity to actual multiplier for scroll
    var scrollMultiplier: Double {
        // Map 0-1 to 1-15 range
        return 1.0 + pow(scrollSensitivity, 1.5) * 14.0
    }

    /// Converts 0-1 acceleration to exponent value
    var mouseAccelerationExponent: Double {
        // Map 0-1 to 1.0-3.0 (1.0 = linear, higher = more acceleration)
        return 1.0 + mouseAcceleration * 2.0
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
        case scrollAcceleration
        case scrollBoostMultiplier
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
        scrollAcceleration = try container.decodeIfPresent(Double.self, forKey: .scrollAcceleration) ?? 0.5
        scrollBoostMultiplier = try container.decodeIfPresent(Double.self, forKey: .scrollBoostMultiplier) ?? 2.0
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
        try container.encode(scrollAcceleration, forKey: .scrollAcceleration)
        try container.encode(scrollBoostMultiplier, forKey: .scrollBoostMultiplier)
    }
}
