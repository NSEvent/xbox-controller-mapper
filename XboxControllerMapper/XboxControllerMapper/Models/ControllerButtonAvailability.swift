import Foundation

extension ControllerButton {
    /// Whether this button is only available on PlayStation controllers (DualSense or DualShock)
    var isPlayStationOnly: Bool {
        switch self {
        case .touchpadButton, .touchpadTwoFingerButton, .touchpadTap, .touchpadTwoFingerTap,
             .touchpadRegionTopLeftClick, .touchpadRegionTopRightClick,
             .touchpadRegionBottomLeftClick, .touchpadRegionBottomRightClick,
             .touchpadRegionTopLeftTouch, .touchpadRegionTopRightTouch,
             .touchpadRegionBottomLeftTouch, .touchpadRegionBottomRightTouch:
            return true  // Available on both DualSense and DualShock
        case .micMute:
            return true  // DualSense only
        case .leftPaddle, .rightPaddle, .leftFunction, .rightFunction:
            return true  // Edge-only, but still PlayStation family
        case .gestureTiltBack, .gestureTiltForward, .gestureSteerLeft, .gestureSteerRight:
            return true  // DualSense gyroscope only
        default:
            return false
        }
    }

    /// Whether this button is only available on DualSense controllers (not DualShock)
    var isDualSenseOnly: Bool {
        switch self {
        case .micMute:
            return true  // DualShock 4 doesn't have mic mute
        case .leftPaddle, .rightPaddle, .leftFunction, .rightFunction:
            return true  // Edge-only
        case .gestureTiltBack, .gestureTiltForward, .gestureSteerLeft, .gestureSteerRight:
            return true  // DualSense gyroscope only
        default:
            return false
        }
    }

    /// Whether this button is only available on Steam Controllers.
    var isSteamControllerOnly: Bool {
        switch self {
        case .leftTouchpadButton, .rightTouchpadButton, .leftTouchpadTap, .rightTouchpadTap,
             .leftTouchpadRegionTopLeftClick, .leftTouchpadRegionTopRightClick,
             .leftTouchpadRegionBottomLeftClick, .leftTouchpadRegionBottomRightClick,
             .leftTouchpadRegionTopLeftTouch, .leftTouchpadRegionTopRightTouch,
             .leftTouchpadRegionBottomLeftTouch, .leftTouchpadRegionBottomRightTouch,
             .rightTouchpadRegionTopLeftClick, .rightTouchpadRegionTopRightClick,
             .rightTouchpadRegionBottomLeftClick, .rightTouchpadRegionBottomRightClick,
             .rightTouchpadRegionTopLeftTouch, .rightTouchpadRegionTopRightTouch,
             .rightTouchpadRegionBottomLeftTouch, .rightTouchpadRegionBottomRightTouch:
            return true
        default:
            return false
        }
    }

    /// Whether this button is only available on Apple TV/Siri Remote devices.
    var isAppleTVRemoteOnly: Bool {
		switch self {
		case .siri, .appleTVRemotePower, .appleTVRemoteVolumeUp, .appleTVRemoteVolumeDown, .appleTVRemoteMute:
			return true
		default:
			return false
		}
    }

    /// Whether this button represents one of the eight touchpad quadrant
    /// variants (4 regions × {touch, click}). Used by the mapping engine for
    /// dispatch and by UI to know how to render the region group.
    var isTouchpadQuadrant: Bool {
        return touchpadRegion != nil
    }

    /// Returns the (region, trigger) pair this button represents, or nil if
    /// it's not one of the quadrant variants.
    var touchpadRegion: TouchpadRegion? {
        switch self {
        case .touchpadRegionTopLeftClick, .touchpadRegionTopLeftTouch,
             .leftTouchpadRegionTopLeftClick, .leftTouchpadRegionTopLeftTouch,
             .rightTouchpadRegionTopLeftClick, .rightTouchpadRegionTopLeftTouch:
            return .topLeft
        case .touchpadRegionTopRightClick, .touchpadRegionTopRightTouch,
             .leftTouchpadRegionTopRightClick, .leftTouchpadRegionTopRightTouch,
             .rightTouchpadRegionTopRightClick, .rightTouchpadRegionTopRightTouch:
            return .topRight
        case .touchpadRegionBottomLeftClick, .touchpadRegionBottomLeftTouch,
             .leftTouchpadRegionBottomLeftClick, .leftTouchpadRegionBottomLeftTouch,
             .rightTouchpadRegionBottomLeftClick, .rightTouchpadRegionBottomLeftTouch:
            return .bottomLeft
        case .touchpadRegionBottomRightClick, .touchpadRegionBottomRightTouch,
             .leftTouchpadRegionBottomRightClick, .leftTouchpadRegionBottomRightTouch,
             .rightTouchpadRegionBottomRightClick, .rightTouchpadRegionBottomRightTouch:
            return .bottomRight
        default: return nil
        }
    }

    var steamTouchpadSide: SteamTouchpadSide? {
        switch self {
        case .leftTouchpadButton, .leftTouchpadTap,
             .leftTouchpadRegionTopLeftClick, .leftTouchpadRegionTopRightClick,
             .leftTouchpadRegionBottomLeftClick, .leftTouchpadRegionBottomRightClick,
             .leftTouchpadRegionTopLeftTouch, .leftTouchpadRegionTopRightTouch,
             .leftTouchpadRegionBottomLeftTouch, .leftTouchpadRegionBottomRightTouch:
            return .left
        case .rightTouchpadButton, .rightTouchpadTap,
             .rightTouchpadRegionTopLeftClick, .rightTouchpadRegionTopRightClick,
             .rightTouchpadRegionBottomLeftClick, .rightTouchpadRegionBottomRightClick,
             .rightTouchpadRegionTopLeftTouch, .rightTouchpadRegionTopRightTouch,
             .rightTouchpadRegionBottomLeftTouch, .rightTouchpadRegionBottomRightTouch:
            return .right
        default:
            return nil
        }
    }

    /// For chord/sequence matching only: which canonical "whole-pad" button
    /// does this button alias for? `.touchpadRegion*Click` aliases for
    /// `.touchpadButton`; `.touchpadRegion*Touch` aliases for `.touchpadTap`.
    /// All other buttons return nil (no alias).
    ///
    /// This is the bridge that lets a chord like `[.touchpadButton, .a]` match
    /// when the user clicks any quadrant in `.quadrants` mode without firing
    /// a duplicate `.touchpadButton` press. The aliasing is *only* consulted
    /// during chord/sequence detection; individual button mappings remain
    /// distinct.
	var chordSequenceAlias: ControllerButton? {
		switch self {
        case .touchpadRegionTopLeftClick, .touchpadRegionTopRightClick,
             .touchpadRegionBottomLeftClick, .touchpadRegionBottomRightClick:
            return .touchpadButton
        case .touchpadRegionTopLeftTouch, .touchpadRegionTopRightTouch,
             .touchpadRegionBottomLeftTouch, .touchpadRegionBottomRightTouch:
            return .touchpadTap
        case .leftTouchpadRegionTopLeftClick, .leftTouchpadRegionTopRightClick,
             .leftTouchpadRegionBottomLeftClick, .leftTouchpadRegionBottomRightClick:
            return .leftTouchpadButton
        case .leftTouchpadRegionTopLeftTouch, .leftTouchpadRegionTopRightTouch,
             .leftTouchpadRegionBottomLeftTouch, .leftTouchpadRegionBottomRightTouch:
            return .leftTouchpadTap
        case .rightTouchpadRegionTopLeftClick, .rightTouchpadRegionTopRightClick,
             .rightTouchpadRegionBottomLeftClick, .rightTouchpadRegionBottomRightClick:
            return .rightTouchpadButton
		case .rightTouchpadRegionTopLeftTouch, .rightTouchpadRegionTopRightTouch,
		     .rightTouchpadRegionBottomLeftTouch, .rightTouchpadRegionBottomRightTouch:
			return .rightTouchpadTap
		case .xboxPaddle1, .xboxPaddle2, .xboxPaddle3, .xboxPaddle4:
			return logicalEquivalent
		default:
			return nil
		}
	}

	var logicalEquivalent: ControllerButton? {
		switch self {
		case .xboxPaddle1:
			return .leftPaddle
		case .xboxPaddle2:
			return .rightPaddle
		case .xboxPaddle3:
			return .leftFunction
		case .xboxPaddle4:
			return .rightFunction
		default:
			return nil
		}
	}

	var physicalEquivalentButtons: [ControllerButton] {
		switch self {
		case .leftPaddle:
			return [.xboxPaddle1]
		case .rightPaddle:
			return [.xboxPaddle2]
		case .leftFunction:
			return [.xboxPaddle3]
		case .rightFunction:
			return [.xboxPaddle4]
		default:
			return []
		}
	}

    /// Returns the trigger mode this quadrant button represents, or nil if
    /// it's not a quadrant variant. `.both` is never returned — it's an
    /// authoring concept, not a button identity.
    var touchpadQuadrantTrigger: TouchpadTriggerMode? {
        switch self {
        case .touchpadRegionTopLeftClick, .touchpadRegionTopRightClick,
             .touchpadRegionBottomLeftClick, .touchpadRegionBottomRightClick,
             .leftTouchpadRegionTopLeftClick, .leftTouchpadRegionTopRightClick,
             .leftTouchpadRegionBottomLeftClick, .leftTouchpadRegionBottomRightClick,
             .rightTouchpadRegionTopLeftClick, .rightTouchpadRegionTopRightClick,
             .rightTouchpadRegionBottomLeftClick, .rightTouchpadRegionBottomRightClick:
            return .click
        case .touchpadRegionTopLeftTouch, .touchpadRegionTopRightTouch,
             .touchpadRegionBottomLeftTouch, .touchpadRegionBottomRightTouch,
             .leftTouchpadRegionTopLeftTouch, .leftTouchpadRegionTopRightTouch,
             .leftTouchpadRegionBottomLeftTouch, .leftTouchpadRegionBottomRightTouch,
             .rightTouchpadRegionTopLeftTouch, .rightTouchpadRegionTopRightTouch,
             .rightTouchpadRegionBottomLeftTouch, .rightTouchpadRegionBottomRightTouch:
            return .touch
        default:
            return nil
        }
    }

    /// Maps a `(region, trigger)` pair to the corresponding ControllerButton
    /// case. `trigger` must be `.click` or `.touch` — `.both` is not a single
    /// button (it's an authoring concept that fans out to both variants).
    static func from(region: TouchpadRegion, trigger: TouchpadTriggerMode) -> ControllerButton? {
        switch (region, trigger) {
        case (.topLeft, .click): return .touchpadRegionTopLeftClick
        case (.topRight, .click): return .touchpadRegionTopRightClick
        case (.bottomLeft, .click): return .touchpadRegionBottomLeftClick
        case (.bottomRight, .click): return .touchpadRegionBottomRightClick
        case (.topLeft, .touch): return .touchpadRegionTopLeftTouch
        case (.topRight, .touch): return .touchpadRegionTopRightTouch
        case (.bottomLeft, .touch): return .touchpadRegionBottomLeftTouch
        case (.bottomRight, .touch): return .touchpadRegionBottomRightTouch
        case (_, .both): return nil
        }
    }

    static func from(
        steamTouchpadSide side: SteamTouchpadSide,
        region: TouchpadRegion,
        trigger: TouchpadTriggerMode
    ) -> ControllerButton? {
        switch (side, region, trigger) {
        case (.left, .topLeft, .click): return .leftTouchpadRegionTopLeftClick
        case (.left, .topRight, .click): return .leftTouchpadRegionTopRightClick
        case (.left, .bottomLeft, .click): return .leftTouchpadRegionBottomLeftClick
        case (.left, .bottomRight, .click): return .leftTouchpadRegionBottomRightClick
        case (.left, .topLeft, .touch): return .leftTouchpadRegionTopLeftTouch
        case (.left, .topRight, .touch): return .leftTouchpadRegionTopRightTouch
        case (.left, .bottomLeft, .touch): return .leftTouchpadRegionBottomLeftTouch
        case (.left, .bottomRight, .touch): return .leftTouchpadRegionBottomRightTouch
        case (.right, .topLeft, .click): return .rightTouchpadRegionTopLeftClick
        case (.right, .topRight, .click): return .rightTouchpadRegionTopRightClick
        case (.right, .bottomLeft, .click): return .rightTouchpadRegionBottomLeftClick
        case (.right, .bottomRight, .click): return .rightTouchpadRegionBottomRightClick
        case (.right, .topLeft, .touch): return .rightTouchpadRegionTopLeftTouch
        case (.right, .topRight, .touch): return .rightTouchpadRegionTopRightTouch
        case (.right, .bottomLeft, .touch): return .rightTouchpadRegionBottomLeftTouch
        case (.right, .bottomRight, .touch): return .rightTouchpadRegionBottomRightTouch
        case (_, _, .both): return nil
        }
    }

    static func steamTouchpadRegionButtons(side: SteamTouchpadSide) -> [ControllerButton] {
        TouchpadRegion.allCases.flatMap { region in
            [
                from(steamTouchpadSide: side, region: region, trigger: .click),
                from(steamTouchpadSide: side, region: region, trigger: .touch),
            ].compactMap { $0 }
        }
    }

    /// Whether this button is one of the virtual joystick direction bindings.
    var isJoystickDirection: Bool {
        joystickDirection != nil
    }

    /// The physical stick side represented by this virtual joystick direction.
    var joystickSide: JoystickSide? {
        switch self {
        case .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
             .leftStickUpLeft, .leftStickUpRight, .leftStickDownLeft, .leftStickDownRight:
            return .left
        case .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
             .rightStickUpLeft, .rightStickUpRight, .rightStickDownLeft, .rightStickDownRight:
            return .right
        default:
            return nil
        }
    }

    /// The joystick direction represented by this virtual button.
    var joystickDirection: JoystickDirection? {
        switch self {
        case .leftStickUp, .rightStickUp: return .up
        case .leftStickDown, .rightStickDown: return .down
        case .leftStickLeft, .rightStickLeft: return .left
        case .leftStickRight, .rightStickRight: return .right
        case .leftStickUpLeft, .rightStickUpLeft: return .upLeft
        case .leftStickUpRight, .rightStickUpRight: return .upRight
        case .leftStickDownLeft, .rightStickDownLeft: return .downLeft
        case .leftStickDownRight, .rightStickDownRight: return .downRight
        default: return nil
        }
    }

    static func joystickDirectionButton(side: JoystickSide, direction: JoystickDirection) -> ControllerButton {
        switch (side, direction) {
        case (.left, .up): return .leftStickUp
        case (.left, .down): return .leftStickDown
        case (.left, .left): return .leftStickLeft
        case (.left, .right): return .leftStickRight
        case (.left, .upLeft): return .leftStickUpLeft
        case (.left, .upRight): return .leftStickUpRight
        case (.left, .downLeft): return .leftStickDownLeft
        case (.left, .downRight): return .leftStickDownRight
        case (.right, .up): return .rightStickUp
        case (.right, .down): return .rightStickDown
        case (.right, .left): return .rightStickLeft
        case (.right, .right): return .rightStickRight
        case (.right, .upLeft): return .rightStickUpLeft
        case (.right, .upRight): return .rightStickUpRight
        case (.right, .downLeft): return .rightStickDownLeft
        case (.right, .downRight): return .rightStickDownRight
        }
    }

    static func joystickDirectionButtons(side: JoystickSide) -> [ControllerButton] {
        [.up, .left, .right, .down]
            .map { joystickDirectionButton(side: side, direction: $0) }
    }

    /// Whether this button is a virtual gesture button (not a physical button)
    var isGestureButton: Bool {
        switch self {
        case .gestureTiltBack, .gestureTiltForward, .gestureSteerLeft, .gestureSteerRight:
            return true
        default:
            return false
        }
    }

    /// Whether this button is only available on DualSense Edge controllers
    var isDualSenseEdgeOnly: Bool {
        switch self {
        case .leftPaddle, .rightPaddle, .leftFunction, .rightFunction:
            return true
        default:
            return false
        }
    }

    /// Whether this button is only available on Xbox Elite controllers
    var isXboxEliteOnly: Bool {
        switch self {
        case .xboxPaddle1, .xboxPaddle2, .xboxPaddle3, .xboxPaddle4:
            return true
        default:
            return false
        }
    }

    /// Buttons available for Xbox controllers (excludes Elite-only paddles)
    static var xboxButtons: [ControllerButton] {
		allCases.filter { !$0.isPlayStationOnly && !$0.isXboxEliteOnly && !$0.isSteamControllerOnly && !$0.isAppleTVRemoteOnly }
    }

    /// Buttons available only on Xbox Elite controllers
    static var xboxEliteButtons: [ControllerButton] {
        [.xboxPaddle1, .xboxPaddle2, .xboxPaddle3, .xboxPaddle4]
    }

    /// Buttons available for DualShock 4 controllers (has touchpad, no mic mute or paddles)
    /// Note: DualShock 4's physical Share button maps to .view (buttonOptions), not .share
    static var dualShockButtons: [ControllerButton] {
		allCases.filter { !$0.isDualSenseOnly && !$0.isXboxEliteOnly && !$0.isSteamControllerOnly && !$0.isAppleTVRemoteOnly && $0 != .share }
    }

    /// Buttons available for DualSense controllers (excludes Share which doesn't exist on standard DualSense)
    static var dualSenseButtons: [ControllerButton] {
		allCases.filter { $0 != .share && !$0.isDualSenseEdgeOnly && !$0.isGestureButton && !$0.isXboxEliteOnly && !$0.isSteamControllerOnly && !$0.isAppleTVRemoteOnly }
    }

    /// Buttons available for Nintendo controllers (Joy-Con, Pro Controller)
    /// Same as Xbox — no touchpad, mic, paddles, or gyro gestures
    static var nintendoButtons: [ControllerButton] {
		allCases.filter { !$0.isPlayStationOnly && !$0.isXboxEliteOnly && !$0.isSteamControllerOnly && !$0.isAppleTVRemoteOnly }
    }

    /// Buttons available for Apple TV/Siri Remote devices.
    static var appleTVRemoteButtons: [ControllerButton] {
		[
			.appleTVRemotePower,
			.dpadUp, .dpadDown, .dpadLeft, .dpadRight,
			.touchpadButton, .touchpadTap, .view, .menu, .xbox, .siri,
			.appleTVRemoteVolumeUp, .appleTVRemoteVolumeDown, .appleTVRemoteMute
		]
    }
}
