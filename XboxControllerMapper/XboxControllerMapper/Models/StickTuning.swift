import Foundation

/// Shared analog-stick response curves. Factored out so per-stick `StickTuning`
/// and the global focus-mode multiplier compute identical curves from a 0-1 knob.
enum JoystickCurves {
    /// Converts 0-1 sensitivity to a mouse pixel-scale multiplier (cubic curve, 2-120).
    static func mouseMultiplier(sensitivity: Double) -> Double {
        2.0 + pow(sensitivity, 3.0) * 118.0
    }

    /// Converts 0-1 sensitivity to a scroll multiplier (1-30).
    static func scrollMultiplier(sensitivity: Double) -> Double {
        1.0 + pow(sensitivity, 1.5) * 29.0
    }

    /// Converts 0-1 acceleration to a mouse exponent (1.0 linear … 3.0 max).
    static func mouseAccelerationExponent(_ acceleration: Double) -> Double {
        1.0 + acceleration * 2.0
    }

    /// Converts 0-1 acceleration to a scroll exponent (1.0 linear … 2.5 max).
    static func scrollAccelerationExponent(_ acceleration: Double) -> Double {
        1.0 + acceleration * 1.5
    }
}

/// Tuning for a single analog stick. Each physical stick (left/right) owns an
/// independent copy, so the two sticks can have different sensitivity,
/// acceleration, and deadzone even when both drive the mouse.
///
/// Replaces the old function-keyed fields on `JoystickSettings`
/// (`mouseSensitivity`/`scrollSensitivity`/…), which were shared across both
/// sticks — two mouse-mode sticks could not have different speeds. The legacy
/// fields are migrated into `JoystickSettings.leftStick` / `.rightStick` on
/// decode (see `JoystickSettings.init(from:)`), fanning the same old values into
/// both sticks so existing behavior is preserved exactly while becoming
/// independently editable.
struct StickTuning: Codable, Equatable {
    /// What this stick does (mouse / scroll / custom / dpad / wasd / arrows / none).
    var mode: StickMode

    // MARK: Mouse-mode knobs
    var mouseSensitivity: Double
    var mouseAcceleration: Double
    var mouseDeadzone: Double
    var invertMouseY: Bool

    // MARK: Scroll-mode knobs
    var scrollSensitivity: Double
    var scrollAcceleration: Double
    var scrollDeadzone: Double
    var invertScrollY: Bool

    // MARK: Custom-direction knobs
    var customHorizontalSliceSize: Double
    var customVerticalSliceSize: Double
    var customDeadzone: Double

    init(
        mode: StickMode,
        mouseSensitivity: Double = 0.5,
        mouseAcceleration: Double = 0.5,
        mouseDeadzone: Double = 0.15,
        invertMouseY: Bool = false,
        scrollSensitivity: Double = 0.5,
        scrollAcceleration: Double = 0.5,
        scrollDeadzone: Double = 0.15,
        invertScrollY: Bool = false,
        customHorizontalSliceSize: Double = JoystickSettings.defaultCustomSliceSize,
        customVerticalSliceSize: Double = JoystickSettings.defaultCustomSliceSize,
        customDeadzone: Double = JoystickSettings.defaultCustomDeadzone
    ) {
        self.mode = mode
        self.mouseSensitivity = mouseSensitivity
        self.mouseAcceleration = mouseAcceleration
        self.mouseDeadzone = mouseDeadzone
        self.invertMouseY = invertMouseY
        self.scrollSensitivity = scrollSensitivity
        self.scrollAcceleration = scrollAcceleration
        self.scrollDeadzone = scrollDeadzone
        self.invertScrollY = invertScrollY
        self.customHorizontalSliceSize = customHorizontalSliceSize
        self.customVerticalSliceSize = customVerticalSliceSize
        self.customDeadzone = customDeadzone
    }

    /// Conventional defaults: left stick drives the mouse, right stick scrolls.
    static let leftDefault = StickTuning(mode: .mouse)
    static let rightDefault = StickTuning(mode: .scroll)

    // MARK: - Derived response values

    var mouseMultiplier: Double { JoystickCurves.mouseMultiplier(sensitivity: mouseSensitivity) }
    var mouseAccelerationExponent: Double { JoystickCurves.mouseAccelerationExponent(mouseAcceleration) }
    var scrollMultiplier: Double { JoystickCurves.scrollMultiplier(sensitivity: scrollSensitivity) }
    var scrollAccelerationExponent: Double { JoystickCurves.scrollAccelerationExponent(scrollAcceleration) }

    func isValid() -> Bool {
        let unit = 0.0...1.0
        return unit.contains(mouseSensitivity) &&
            unit.contains(mouseAcceleration) &&
            (0.0...0.99).contains(mouseDeadzone) &&
            unit.contains(scrollSensitivity) &&
            unit.contains(scrollAcceleration) &&
            (0.0...0.99).contains(scrollDeadzone) &&
            unit.contains(customHorizontalSliceSize) &&
            unit.contains(customVerticalSliceSize) &&
            unit.contains(customDeadzone)
    }

    // MARK: - Codable (lenient: unknown mode → keep, clamp ranges, default missing)

    enum CodingKeys: String, CodingKey {
        case mode
        case mouseSensitivity, mouseAcceleration, mouseDeadzone, invertMouseY
        case scrollSensitivity, scrollAcceleration, scrollDeadzone, invertScrollY
        case customHorizontalSliceSize, customVerticalSliceSize, customDeadzone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let unit = 0.0...1.0
        mode = try container.decodeLenient(.mode, default: .mouse)
        mouseSensitivity = try container.decode(.mouseSensitivity, default: 0.5, clampedTo: unit)
        mouseAcceleration = try container.decode(.mouseAcceleration, default: 0.5, clampedTo: unit)
        mouseDeadzone = try container.decode(.mouseDeadzone, default: 0.15, clampedTo: 0.0...0.99)
        invertMouseY = try container.decode(.invertMouseY, default: false)
        scrollSensitivity = try container.decode(.scrollSensitivity, default: 0.5, clampedTo: unit)
        scrollAcceleration = try container.decode(.scrollAcceleration, default: 0.5, clampedTo: unit)
        scrollDeadzone = try container.decode(.scrollDeadzone, default: 0.15, clampedTo: 0.0...0.99)
        invertScrollY = try container.decode(.invertScrollY, default: false)
        customHorizontalSliceSize = try container.decode(
            .customHorizontalSliceSize, default: JoystickSettings.defaultCustomSliceSize, clampedTo: unit)
        customVerticalSliceSize = try container.decode(
            .customVerticalSliceSize, default: JoystickSettings.defaultCustomSliceSize, clampedTo: unit)
        customDeadzone = try container.decode(
            .customDeadzone, default: JoystickSettings.defaultCustomDeadzone, clampedTo: unit)
    }
}

/// An optional, per-field override of a `StickTuning`, applied when a layer is
/// active. `nil` field = inherit the profile-level stick tuning; a set field
/// replaces it. Mirrors the layer transparency model used for button mappings:
/// a layer only changes what it explicitly sets, otherwise it falls through to
/// the base profile.
struct StickTuningOverride: Codable, Equatable {
    var mode: StickMode?
    var mouseSensitivity: Double?
    var mouseAcceleration: Double?
    var mouseDeadzone: Double?
    var invertMouseY: Bool?
    var scrollSensitivity: Double?
    var scrollAcceleration: Double?
    var scrollDeadzone: Double?
    var invertScrollY: Bool?
    var customHorizontalSliceSize: Double?
    var customVerticalSliceSize: Double?
    var customDeadzone: Double?

    /// True when nothing is overridden — the layer fully inherits the base stick.
    var isEmpty: Bool {
        mode == nil &&
            mouseSensitivity == nil && mouseAcceleration == nil && mouseDeadzone == nil && invertMouseY == nil &&
            scrollSensitivity == nil && scrollAcceleration == nil && scrollDeadzone == nil && invertScrollY == nil &&
            customHorizontalSliceSize == nil && customVerticalSliceSize == nil && customDeadzone == nil
    }

    /// Overlays the set fields onto `base`, leaving unset fields inherited.
    func applied(to base: StickTuning) -> StickTuning {
        var t = base
        if let mode { t.mode = mode }
        if let mouseSensitivity { t.mouseSensitivity = mouseSensitivity }
        if let mouseAcceleration { t.mouseAcceleration = mouseAcceleration }
        if let mouseDeadzone { t.mouseDeadzone = mouseDeadzone }
        if let invertMouseY { t.invertMouseY = invertMouseY }
        if let scrollSensitivity { t.scrollSensitivity = scrollSensitivity }
        if let scrollAcceleration { t.scrollAcceleration = scrollAcceleration }
        if let scrollDeadzone { t.scrollDeadzone = scrollDeadzone }
        if let invertScrollY { t.invertScrollY = invertScrollY }
        if let customHorizontalSliceSize { t.customHorizontalSliceSize = customHorizontalSliceSize }
        if let customVerticalSliceSize { t.customVerticalSliceSize = customVerticalSliceSize }
        if let customDeadzone { t.customDeadzone = customDeadzone }
        return t
    }

    // MARK: - Codable (lenient mode so a newer build's StickMode never throws out the layer)

    enum CodingKeys: String, CodingKey {
        case mode
        case mouseSensitivity, mouseAcceleration, mouseDeadzone, invertMouseY
        case scrollSensitivity, scrollAcceleration, scrollDeadzone, invertScrollY
        case customHorizontalSliceSize, customVerticalSliceSize, customDeadzone
    }

    init(
        mode: StickMode? = nil,
        mouseSensitivity: Double? = nil,
        mouseAcceleration: Double? = nil,
        mouseDeadzone: Double? = nil,
        invertMouseY: Bool? = nil,
        scrollSensitivity: Double? = nil,
        scrollAcceleration: Double? = nil,
        scrollDeadzone: Double? = nil,
        invertScrollY: Bool? = nil,
        customHorizontalSliceSize: Double? = nil,
        customVerticalSliceSize: Double? = nil,
        customDeadzone: Double? = nil
    ) {
        self.mode = mode
        self.mouseSensitivity = mouseSensitivity
        self.mouseAcceleration = mouseAcceleration
        self.mouseDeadzone = mouseDeadzone
        self.invertMouseY = invertMouseY
        self.scrollSensitivity = scrollSensitivity
        self.scrollAcceleration = scrollAcceleration
        self.scrollDeadzone = scrollDeadzone
        self.invertScrollY = invertScrollY
        self.customHorizontalSliceSize = customHorizontalSliceSize
        self.customVerticalSliceSize = customVerticalSliceSize
        self.customDeadzone = customDeadzone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Lenient: an unknown StickMode raw value (newer build) → nil ("inherit")
        // instead of throwing and losing the whole override / layer.
        mode = try container.decodeLenient(.mode)
        mouseSensitivity = try container.decodeIfPresent(Double.self, forKey: .mouseSensitivity)
        mouseAcceleration = try container.decodeIfPresent(Double.self, forKey: .mouseAcceleration)
        mouseDeadzone = try container.decodeIfPresent(Double.self, forKey: .mouseDeadzone)
        invertMouseY = try container.decodeIfPresent(Bool.self, forKey: .invertMouseY)
        scrollSensitivity = try container.decodeIfPresent(Double.self, forKey: .scrollSensitivity)
        scrollAcceleration = try container.decodeIfPresent(Double.self, forKey: .scrollAcceleration)
        scrollDeadzone = try container.decodeIfPresent(Double.self, forKey: .scrollDeadzone)
        invertScrollY = try container.decodeIfPresent(Bool.self, forKey: .invertScrollY)
        customHorizontalSliceSize = try container.decodeIfPresent(Double.self, forKey: .customHorizontalSliceSize)
        customVerticalSliceSize = try container.decodeIfPresent(Double.self, forKey: .customVerticalSliceSize)
        customDeadzone = try container.decodeIfPresent(Double.self, forKey: .customDeadzone)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(mouseSensitivity, forKey: .mouseSensitivity)
        try container.encodeIfPresent(mouseAcceleration, forKey: .mouseAcceleration)
        try container.encodeIfPresent(mouseDeadzone, forKey: .mouseDeadzone)
        try container.encodeIfPresent(invertMouseY, forKey: .invertMouseY)
        try container.encodeIfPresent(scrollSensitivity, forKey: .scrollSensitivity)
        try container.encodeIfPresent(scrollAcceleration, forKey: .scrollAcceleration)
        try container.encodeIfPresent(scrollDeadzone, forKey: .scrollDeadzone)
        try container.encodeIfPresent(invertScrollY, forKey: .invertScrollY)
        try container.encodeIfPresent(customHorizontalSliceSize, forKey: .customHorizontalSliceSize)
        try container.encodeIfPresent(customVerticalSliceSize, forKey: .customVerticalSliceSize)
        try container.encodeIfPresent(customDeadzone, forKey: .customDeadzone)
    }
}
