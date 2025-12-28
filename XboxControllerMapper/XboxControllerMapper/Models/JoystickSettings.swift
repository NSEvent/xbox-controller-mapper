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

    static let `default` = JoystickSettings()

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
