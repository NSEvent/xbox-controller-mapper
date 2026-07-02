import Foundation

/// Mode for each analog stick
enum StickMode: String, Codable, CaseIterable {
    case none = "none"
    case mouse = "mouse"
    case scroll = "scroll"
    case wasdKeys = "wasdKeys"
    case arrowKeys = "arrowKeys"
    case custom = "custom"
    /// Stick deflection drives the controller's own D-pad buttons
    /// (.dpadUp/.dpadDown/.dpadLeft/.dpadRight). Useful for stickless pads
    /// (8BitDo Zero 2 / Micro) where the physical d-pad feeds the left stick:
    /// this routes it back to true d-pad controls instead of the mouse.
    case dpad = "dpad"

    static let visibleModes: [StickMode] = [.none, .mouse, .scroll, .custom, .dpad]

    var isVisibleInUI: Bool {
        Self.visibleModes.contains(self)
    }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .mouse: return "Mouse"
        case .scroll: return "Scroll"
        case .wasdKeys: return "WASD"
        case .arrowKeys: return "Arrows"
        case .custom: return "Custom"
        case .dpad: return "D-Pad"
        }
    }

    var exposesJoystickDirections: Bool {
        switch self {
        case .custom:
            return true
        case .none, .mouse, .scroll, .wasdKeys, .arrowKeys, .dpad:
            return false
        }
    }
}

/// Settings for joystick behavior.
///
/// Per-stick response (mode, sensitivity, acceleration, deadzone, invert, custom
/// slices) lives in `leftStick` / `rightStick` (`StickTuning`), so the two sticks
/// are independently tunable even when both drive the mouse. Everything else here
/// is genuinely global (touchpad, focus mode, gyro aiming, motion gestures,
/// scroll double-tap boost).
struct JoystickSettings: Codable, Equatable {
    static let defaultCustomSliceSize = 0.75
    static let defaultCustomDeadzone = 0.22
    static let defaultTouchpadDeadzone = 0.005

    /// Per-stick tuning for the left analog stick (defaults to mouse).
    var leftStick: StickTuning = .leftDefault

    /// Per-stick tuning for the right analog stick (defaults to scroll).
    var rightStick: StickTuning = .rightDefault

    /// Touchpad sensitivity (0.0 - 1.0)
    var touchpadSensitivity: Double = 0.5

    /// Touchpad acceleration curve (0.0 = linear, 1.0 = max acceleration)
    var touchpadAcceleration: Double = 0.5

    /// Deadzone for touchpad movement (0.0 - 0.03)
    var touchpadDeadzone: Double = Self.defaultTouchpadDeadzone

    /// Smoothing amount for touchpad movement (0.0 - 1.0)
    var touchpadSmoothing: Double = 0.4

    /// When true, touchpad region clicks only fire if a finger is actively touching
    /// the pad at the moment of click. Prevents stale-position misfires (e.g. clicking
    /// after the finger has lifted off, where the last known position falls into a
    /// quadrant the user never intended). When false, the last known touch position
    /// is used regardless of whether a finger is currently down.
    var requireActiveTouchForRegionClick: Bool = true

    /// Two-finger pan sensitivity (0.0 - 1.0)
    var touchpadPanSensitivity: Double = 0.5

	/// Enables one-finger circular scrolling around the Apple TV remote clickpad edge.
	var appleTVRemoteCircularScrollEnabled: Bool = true

	/// Apple TV remote circular edge-scroll sensitivity (0.0 - 1.0).
	var appleTVRemoteCircularScrollSensitivity: Double = 0.5

    /// Reverse horizontal touchpad scrolling / panning.
    var touchpadInvertScrollX: Bool = false

    /// Reverse vertical touchpad scrolling / panning.
    var touchpadInvertScrollY: Bool = false

    /// Pan to zoom ratio threshold (low = easier to zoom, high = easier to pan)
    var touchpadZoomToPanRatio: Double = 1.95

    /// Whether to use native magnify gestures (true) or Cmd+Plus/Minus (false) for zoom
    var touchpadUseNativeZoom: Bool = true

    /// When true, single-finger touchpad movement no longer drives the system cursor.
    /// Two-finger gestures, taps, region clicks, and swipe typing are unaffected.
    /// Applies to DualSense, DualSense Edge, and DualShock 4 (same touchpad pipeline).
    var disableTouchpadAsMouse: Bool = false

    /// Multiplier applied to scroll speed after a double-tap up/down
    var scrollBoostMultiplier: Double = 2.0

    /// Sensitivity to use when focus modifier is held (0.0 - 1.0)
    var focusModeSensitivity: Double = 0.1

    /// Modifier that triggers focus mode (slower mouse speed)
    var focusModeModifier: ModifierFlags = .command

    /// Whether gyroscope aiming is enabled during focus mode.
    var gyroAimingEnabled: Bool = false

    /// Sensitivity for gyroscope aiming (0.0 - 1.0)
    var gyroAimingSensitivity: Double = 0.3

    /// Deadzone for gyroscope aiming (0.0 - 1.0, rad/s threshold)
    var gyroAimingDeadzone: Double = 0.3

    /// How mouse movement is posted when a game captures the mouse (pointer lock).
    /// `.auto` switches to relative delta-only events while the system cursor is
    /// hidden, so FPS aiming never stops at screen edges.
    var pointerLockMouseMode: PointerLockMouseMode = .auto

    /// Motion gesture sensitivity (0.0 = hard to trigger, 1.0 = very sensitive)
    var gestureSensitivity: Double = 0.5

    /// Motion gesture cooldown (0.0 = fast repeat, 1.0 = slow repeat)
    var gestureCooldown: Double = 0.5

    static let `default` = JoystickSettings()

    /// Tuning for the given side.
    func stick(_ side: JoystickSide) -> StickTuning {
        side == .left ? leftStick : rightStick
    }

    /// Converts 0-1 gyro aiming sensitivity to pixel-scale multiplier (cubic curve)
    var gyroAimingMultiplier: Double {
        return 1.0 + pow(gyroAimingSensitivity, 3.0) * 20.0
    }

    func chordSequenceJoystickDirectionButtons(side: JoystickSide) -> [ControllerButton] {
        let mode = stick(side).mode
        guard mode.exposesJoystickDirections else { return [] }
        return ControllerButton.joystickDirectionButtons(side: side)
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
        return leftStick.isValid() &&
               rightStick.isValid() &&
               range.contains(touchpadSensitivity) &&
               range.contains(touchpadAcceleration) &&
               (0.0...0.03).contains(touchpadDeadzone) &&
               range.contains(touchpadSmoothing) &&
               range.contains(touchpadPanSensitivity) &&
			   range.contains(appleTVRemoteCircularScrollSensitivity) &&
               (0.5...5.0).contains(touchpadZoomToPanRatio) &&
               (1.0...4.0).contains(scrollBoostMultiplier) &&
               range.contains(focusModeSensitivity) &&
               range.contains(gyroAimingSensitivity) &&
               range.contains(gyroAimingDeadzone) &&
               range.contains(gestureSensitivity) &&
               range.contains(gestureCooldown)
    }

    /// Converts 0-1 focus sensitivity to actual multiplier for mouse
    var focusMultiplier: Double {
        return JoystickCurves.mouseMultiplier(sensitivity: focusModeSensitivity)
    }

    func calibratedTouchpadValue(_ raw: Double, boost: Double) -> Double {
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

    /// Converts 0-1 acceleration to exponent value
    var touchpadAccelerationExponent: Double {
        // Map 0-1 to 1.0-3.0 (1.0 = linear, higher = more acceleration)
        return 1.0 + effectiveTouchpadAcceleration * 2.0
    }
}

// MARK: - Custom Codable (per-stick migration + global field defaults)

extension JoystickSettings {
    enum CodingKeys: String, CodingKey {
        // New per-stick representation.
        case leftStick
        case rightStick
        // Global fields.
        case touchpadSensitivity
        case touchpadAcceleration
        case touchpadDeadzone
        case touchpadSmoothing
        case requireActiveTouchForRegionClick
        case touchpadPanSensitivity
		case appleTVRemoteCircularScrollEnabled
		case appleTVRemoteCircularScrollSensitivity
        case touchpadInvertScrollX
        case touchpadInvertScrollY
        case touchpadZoomToPanRatio
        case touchpadUseNativeZoom
        case disableTouchpadAsMouse
        case scrollBoostMultiplier
        case focusModeSensitivity
        case focusModeModifier
        case gyroAimingEnabled
        case gyroAimingSensitivity
        case gyroAimingDeadzone
        case pointerLockMouseMode
        case gestureSensitivity
        case gestureCooldown
        // Legacy function-keyed per-stick fields — decoded only when the new
        // `leftStick`/`rightStick` keys are absent, and re-encoded for downgrade
        // safety (see encode).
        case mouseSensitivity
        case scrollSensitivity
        case mouseDeadzone
        case scrollDeadzone
        case invertMouseY
        case invertScrollY
        case mouseAcceleration
        case scrollAcceleration
        case leftStickMode
        case rightStickMode
        case leftStickCustomHorizontalSliceSize
        case leftStickCustomVerticalSliceSize
        case leftStickCustomDeadzone
        case rightStickCustomHorizontalSliceSize
        case rightStickCustomVerticalSliceSize
        case rightStickCustomDeadzone
        case leftStickCustomSliceDeadzone // Legacy shared neutral gap.
        case rightStickCustomSliceDeadzone // Legacy shared neutral gap.
        case leftStickCustomEightWay // Legacy, ignored after 4-way-only custom mode.
        case rightStickCustomEightWay // Legacy, ignored after 4-way-only custom mode.
        case leftStickHorizontalAxisRange // Legacy axis UI, migrated as horizontal slice size.
        case leftStickVerticalAxisRange // Legacy axis UI, migrated as vertical slice size.
        case rightStickHorizontalAxisRange // Legacy axis UI, migrated as horizontal slice size.
        case rightStickVerticalAxisRange // Legacy axis UI, migrated as vertical slice size.
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let unit = 0.0...1.0

        touchpadSensitivity = try container.decode(.touchpadSensitivity, default: 0.5, clampedTo: unit)
        touchpadAcceleration = try container.decode(.touchpadAcceleration, default: 0.5, clampedTo: unit)
        touchpadDeadzone = try container.decode(.touchpadDeadzone, default: Self.defaultTouchpadDeadzone, clampedTo: 0.0...0.03)
        touchpadSmoothing = try container.decode(.touchpadSmoothing, default: 0.4, clampedTo: unit)
        requireActiveTouchForRegionClick = try container.decode(.requireActiveTouchForRegionClick, default: true)
        touchpadPanSensitivity = try container.decode(.touchpadPanSensitivity, default: 0.5, clampedTo: unit)
		appleTVRemoteCircularScrollEnabled = try container.decode(.appleTVRemoteCircularScrollEnabled, default: true)
		appleTVRemoteCircularScrollSensitivity = try container.decode(
			.appleTVRemoteCircularScrollSensitivity,
			default: touchpadPanSensitivity,
			clampedTo: unit
		)
        touchpadInvertScrollX = try container.decode(.touchpadInvertScrollX, default: false)
        let legacyInvertScrollY = try container.decode(.invertScrollY, default: false)
        touchpadInvertScrollY = try container.decode(.touchpadInvertScrollY, default: legacyInvertScrollY)
        touchpadZoomToPanRatio = try container.decode(.touchpadZoomToPanRatio, default: 1.95, clampedTo: 0.5...5.0)
        touchpadUseNativeZoom = try container.decode(.touchpadUseNativeZoom, default: true)
        disableTouchpadAsMouse = try container.decode(.disableTouchpadAsMouse, default: false)
        scrollBoostMultiplier = try container.decode(.scrollBoostMultiplier, default: 2.0, clampedTo: 1.0...4.0)
        focusModeSensitivity = try container.decode(.focusModeSensitivity, default: 0.2, clampedTo: unit)
        focusModeModifier = try container.decode(.focusModeModifier, default: .command)
        gyroAimingEnabled = try container.decode(.gyroAimingEnabled, default: false)
        gyroAimingSensitivity = try container.decode(.gyroAimingSensitivity, default: 0.3, clampedTo: unit)
        gyroAimingDeadzone = try container.decode(.gyroAimingDeadzone, default: 0.3, clampedTo: unit)
        // Lenient: a mode added by a newer build degrades to .auto on downgrade.
        pointerLockMouseMode = try container.decodeLenient(.pointerLockMouseMode, default: PointerLockMouseMode.auto)
        gestureSensitivity = try container.decode(.gestureSensitivity, default: 0.5, clampedTo: unit)
        gestureCooldown = try container.decode(.gestureCooldown, default: 0.5, clampedTo: unit)

        // Per-stick tuning: prefer the new nested representation; otherwise migrate
        // from the legacy function-keyed flat fields, fanning the shared mouse/scroll
        // values into BOTH sticks so old configs keep identical behavior while
        // becoming independently editable.
        let migrated = try Self.migrateLegacyStickTunings(from: container)
        leftStick = try container.decodeIfPresent(StickTuning.self, forKey: .leftStick) ?? migrated.left
        rightStick = try container.decodeIfPresent(StickTuning.self, forKey: .rightStick) ?? migrated.right
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // New canonical per-stick representation.
        try container.encode(leftStick, forKey: .leftStick)
        try container.encode(rightStick, forKey: .rightStick)

        // Global fields.
        try container.encode(touchpadSensitivity, forKey: .touchpadSensitivity)
        try container.encode(touchpadAcceleration, forKey: .touchpadAcceleration)
        try container.encode(touchpadDeadzone, forKey: .touchpadDeadzone)
        try container.encode(touchpadSmoothing, forKey: .touchpadSmoothing)
        try container.encode(requireActiveTouchForRegionClick, forKey: .requireActiveTouchForRegionClick)
        try container.encode(touchpadPanSensitivity, forKey: .touchpadPanSensitivity)
		try container.encode(appleTVRemoteCircularScrollEnabled, forKey: .appleTVRemoteCircularScrollEnabled)
		try container.encode(appleTVRemoteCircularScrollSensitivity, forKey: .appleTVRemoteCircularScrollSensitivity)
        try container.encode(touchpadInvertScrollX, forKey: .touchpadInvertScrollX)
        try container.encode(touchpadInvertScrollY, forKey: .touchpadInvertScrollY)
        try container.encode(touchpadZoomToPanRatio, forKey: .touchpadZoomToPanRatio)
        try container.encode(touchpadUseNativeZoom, forKey: .touchpadUseNativeZoom)
        try container.encode(disableTouchpadAsMouse, forKey: .disableTouchpadAsMouse)
        try container.encode(scrollBoostMultiplier, forKey: .scrollBoostMultiplier)
        try container.encode(focusModeSensitivity, forKey: .focusModeSensitivity)
        try container.encode(focusModeModifier, forKey: .focusModeModifier)
        try container.encode(gyroAimingEnabled, forKey: .gyroAimingEnabled)
        try container.encode(gyroAimingSensitivity, forKey: .gyroAimingSensitivity)
        try container.encode(gyroAimingDeadzone, forKey: .gyroAimingDeadzone)
        try container.encode(pointerLockMouseMode, forKey: .pointerLockMouseMode)
        try container.encode(gestureSensitivity, forKey: .gestureSensitivity)
        try container.encode(gestureCooldown, forKey: .gestureCooldown)

        // Legacy compatibility: keep the old flat fields populated so a profile
        // saved/exported by this build still loads sane values on a pre-per-stick
        // build (left = conventional mouse stick, right = conventional scroll stick).
        // A newer build ignores these and reads leftStick/rightStick instead.
        try container.encode(leftStick.mouseSensitivity, forKey: .mouseSensitivity)
        try container.encode(leftStick.mouseAcceleration, forKey: .mouseAcceleration)
        try container.encode(leftStick.mouseDeadzone, forKey: .mouseDeadzone)
        try container.encode(leftStick.invertMouseY, forKey: .invertMouseY)
        try container.encode(rightStick.scrollSensitivity, forKey: .scrollSensitivity)
        try container.encode(rightStick.scrollAcceleration, forKey: .scrollAcceleration)
        try container.encode(rightStick.scrollDeadzone, forKey: .scrollDeadzone)
        try container.encode(rightStick.invertScrollY, forKey: .invertScrollY)
        try container.encode(leftStick.mode, forKey: .leftStickMode)
        try container.encode(rightStick.mode, forKey: .rightStickMode)
        try container.encode(leftStick.customHorizontalSliceSize, forKey: .leftStickCustomHorizontalSliceSize)
        try container.encode(leftStick.customVerticalSliceSize, forKey: .leftStickCustomVerticalSliceSize)
        try container.encode(leftStick.customDeadzone, forKey: .leftStickCustomDeadzone)
        try container.encode(rightStick.customHorizontalSliceSize, forKey: .rightStickCustomHorizontalSliceSize)
        try container.encode(rightStick.customVerticalSliceSize, forKey: .rightStickCustomVerticalSliceSize)
        try container.encode(rightStick.customDeadzone, forKey: .rightStickCustomDeadzone)
    }

    /// Rebuilds per-stick tuning from the legacy function-keyed fields. Both sticks
    /// inherit the same legacy mouse* and scroll* values (which were shared before),
    /// plus their own mode and custom slices.
    private static func migrateLegacyStickTunings(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> (left: StickTuning, right: StickTuning) {
        let unit = 0.0...1.0
        let mouseSensitivity = try container.decode(.mouseSensitivity, default: 0.5, clampedTo: unit)
        let scrollSensitivity = try container.decode(.scrollSensitivity, default: 0.5, clampedTo: unit)
        let mouseDeadzone = try container.decode(.mouseDeadzone, default: 0.15, clampedTo: 0.0...0.99)
        let scrollDeadzone = try container.decode(.scrollDeadzone, default: 0.15, clampedTo: 0.0...0.99)
        let invertMouseY = try container.decode(.invertMouseY, default: false)
        let invertScrollY = try container.decode(.invertScrollY, default: false)
        let mouseAcceleration = try container.decode(.mouseAcceleration, default: 0.5, clampedTo: unit)
        let scrollAcceleration = try container.decode(.scrollAcceleration, default: 0.5, clampedTo: unit)
        // Lenient: a StickMode case added by a newer build degrades to the default
        // on downgrade rather than throwing out the whole config.
        let leftMode = try container.decodeLenient(.leftStickMode, default: StickMode.mouse)
        let rightMode = try container.decodeLenient(.rightStickMode, default: StickMode.scroll)

        let leftLegacySharedSize = sliceSize(
            fromLegacyDeadzone: try container.decodeIfPresent(Double.self, forKey: .leftStickCustomSliceDeadzone)
        )
        let rightLegacySharedSize = sliceSize(
            fromLegacyDeadzone: try container.decodeIfPresent(Double.self, forKey: .rightStickCustomSliceDeadzone)
        )
        let leftLegacyHorizontalSize = try container.decode(.leftStickHorizontalAxisRange, default: leftLegacySharedSize, clampedTo: unit)
        let leftLegacyVerticalSize = try container.decode(.leftStickVerticalAxisRange, default: leftLegacySharedSize, clampedTo: unit)
        let rightLegacyHorizontalSize = try container.decode(.rightStickHorizontalAxisRange, default: rightLegacySharedSize, clampedTo: unit)
        let rightLegacyVerticalSize = try container.decode(.rightStickVerticalAxisRange, default: rightLegacySharedSize, clampedTo: unit)

        let leftCustomHorizontal = try container.decode(.leftStickCustomHorizontalSliceSize, default: leftLegacyHorizontalSize, clampedTo: unit)
        let leftCustomVertical = try container.decode(.leftStickCustomVerticalSliceSize, default: leftLegacyVerticalSize, clampedTo: unit)
        let leftCustomDeadzone = try container.decode(
            .leftStickCustomDeadzone,
            default: container.contains(.mouseDeadzone) ? mouseDeadzone : Self.defaultCustomDeadzone,
            clampedTo: unit
        )
        let rightCustomHorizontal = try container.decode(.rightStickCustomHorizontalSliceSize, default: rightLegacyHorizontalSize, clampedTo: unit)
        let rightCustomVertical = try container.decode(.rightStickCustomVerticalSliceSize, default: rightLegacyVerticalSize, clampedTo: unit)
        let rightCustomDeadzone = try container.decode(
            .rightStickCustomDeadzone,
            default: container.contains(.scrollDeadzone) ? scrollDeadzone : Self.defaultCustomDeadzone,
            clampedTo: unit
        )

        let left = StickTuning(
            mode: leftMode,
            mouseSensitivity: mouseSensitivity,
            mouseAcceleration: mouseAcceleration,
            mouseDeadzone: mouseDeadzone,
            invertMouseY: invertMouseY,
            scrollSensitivity: scrollSensitivity,
            scrollAcceleration: scrollAcceleration,
            scrollDeadzone: scrollDeadzone,
            invertScrollY: invertScrollY,
            customHorizontalSliceSize: leftCustomHorizontal,
            customVerticalSliceSize: leftCustomVertical,
            customDeadzone: leftCustomDeadzone
        )
        let right = StickTuning(
            mode: rightMode,
            mouseSensitivity: mouseSensitivity,
            mouseAcceleration: mouseAcceleration,
            mouseDeadzone: mouseDeadzone,
            invertMouseY: invertMouseY,
            scrollSensitivity: scrollSensitivity,
            scrollAcceleration: scrollAcceleration,
            scrollDeadzone: scrollDeadzone,
            invertScrollY: invertScrollY,
            customHorizontalSliceSize: rightCustomHorizontal,
            customVerticalSliceSize: rightCustomVertical,
            customDeadzone: rightCustomDeadzone
        )
        return (left, right)
    }

    private static func sliceSize(fromLegacyDeadzone deadzone: Double?) -> Double {
        guard let deadzone, deadzone.isFinite else { return defaultCustomSliceSize }
        let clampedDeadzone = min(1.0, max(0.0, deadzone))
        return 1.0 - clampedDeadzone * (2.0 / 3.0)
    }
}
