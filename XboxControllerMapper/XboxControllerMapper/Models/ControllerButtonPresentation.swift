import Foundation

extension ControllerButton {
    /// Human-readable display name
    var displayName: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .leftBumper: return "LB"
        case .rightBumper: return "RB"
        case .leftTrigger: return "LT"
        case .rightTrigger: return "RT"
        case .dpadUp: return "D-pad Up"
        case .dpadDown: return "D-pad Down"
        case .dpadLeft: return "D-pad Left"
        case .dpadRight: return "D-pad Right"
        case .menu: return "Menu"
        case .view: return "View"
        case .share: return "Share"
        case .xbox: return "Xbox"
		case .siri: return "Siri"
		case .appleTVRemotePower: return "Power"
		case .appleTVRemoteVolumeUp: return "Volume Up"
		case .appleTVRemoteVolumeDown: return "Volume Down"
		case .appleTVRemoteMute: return "Mute"
        case .leftThumbstick: return "Left Stick"
        case .rightThumbstick: return "Right Stick"
        case .leftStickUp: return "Left Stick Up"
        case .leftStickDown: return "Left Stick Down"
        case .leftStickLeft: return "Left Stick Left"
        case .leftStickRight: return "Left Stick Right"
        case .leftStickUpLeft: return "Left Stick Up-Left"
        case .leftStickUpRight: return "Left Stick Up-Right"
        case .leftStickDownLeft: return "Left Stick Down-Left"
        case .leftStickDownRight: return "Left Stick Down-Right"
        case .rightStickUp: return "Right Stick Up"
        case .rightStickDown: return "Right Stick Down"
        case .rightStickLeft: return "Right Stick Left"
        case .rightStickRight: return "Right Stick Right"
        case .rightStickUpLeft: return "Right Stick Up-Left"
        case .rightStickUpRight: return "Right Stick Up-Right"
        case .rightStickDownLeft: return "Right Stick Down-Left"
        case .rightStickDownRight: return "Right Stick Down-Right"
        case .touchpadButton: return "Touchpad Press"
        case .touchpadTwoFingerButton: return "Touchpad 2-Finger Press"
        case .touchpadTap: return "Touchpad Tap"
        case .touchpadTwoFingerTap: return "Touchpad 2-Finger Tap"
        case .micMute: return "Mic Mute"
        case .leftTouchpadButton: return "Left Pad Press"
        case .rightTouchpadButton: return "Right Pad Press"
        case .leftTouchpadTap: return "Left Pad Tap"
        case .rightTouchpadTap: return "Right Pad Tap"
        case .leftTouchpadRegionTopLeftClick: return "Left Top-Left Click"
        case .leftTouchpadRegionTopRightClick: return "Left Top-Right Click"
        case .leftTouchpadRegionBottomLeftClick: return "Left Bottom-Left Click"
        case .leftTouchpadRegionBottomRightClick: return "Left Bottom-Right Click"
        case .leftTouchpadRegionTopLeftTouch: return "Left Top-Left Tap"
        case .leftTouchpadRegionTopRightTouch: return "Left Top-Right Tap"
        case .leftTouchpadRegionBottomLeftTouch: return "Left Bottom-Left Tap"
        case .leftTouchpadRegionBottomRightTouch: return "Left Bottom-Right Tap"
        case .rightTouchpadRegionTopLeftClick: return "Right Top-Left Click"
        case .rightTouchpadRegionTopRightClick: return "Right Top-Right Click"
        case .rightTouchpadRegionBottomLeftClick: return "Right Bottom-Left Click"
        case .rightTouchpadRegionBottomRightClick: return "Right Bottom-Right Click"
        case .rightTouchpadRegionTopLeftTouch: return "Right Top-Left Tap"
        case .rightTouchpadRegionTopRightTouch: return "Right Top-Right Tap"
        case .rightTouchpadRegionBottomLeftTouch: return "Right Bottom-Left Tap"
        case .rightTouchpadRegionBottomRightTouch: return "Right Bottom-Right Tap"
        case .touchpadRegionTopLeftClick: return "Top-Left Click"
        case .touchpadRegionTopRightClick: return "Top-Right Click"
        case .touchpadRegionBottomLeftClick: return "Bottom-Left Click"
        case .touchpadRegionBottomRightClick: return "Bottom-Right Click"
        case .touchpadRegionTopLeftTouch: return "Top-Left Touch"
        case .touchpadRegionTopRightTouch: return "Top-Right Touch"
        case .touchpadRegionBottomLeftTouch: return "Bottom-Left Touch"
        case .touchpadRegionBottomRightTouch: return "Bottom-Right Touch"
        case .leftPaddle: return "Left Paddle"
        case .rightPaddle: return "Right Paddle"
        case .leftFunction: return "Left Fn"
        case .rightFunction: return "Right Fn"
        case .xboxPaddle1: return "Upper Left Paddle"
        case .xboxPaddle2: return "Upper Right Paddle"
        case .xboxPaddle3: return "Lower Left Paddle"
        case .xboxPaddle4: return "Lower Right Paddle"
        case .gestureTiltBack: return "Tilt Back"
        case .gestureTiltForward: return "Tilt Forward"
        case .gestureSteerLeft: return "Steer Left"
        case .gestureSteerRight: return "Steer Right"
        }
    }

    /// Display name appropriate for the controller type
    func displayName(forDualSense isDualSense: Bool) -> String {
        guard isDualSense else { return displayName }
        switch self {
        case .a: return "Cross"
        case .b: return "Circle"
        case .x: return "Square"
        case .y: return "Triangle"
        case .leftBumper: return "L1"
        case .rightBumper: return "R1"
        case .leftTrigger: return "L2"
        case .rightTrigger: return "R2"
        case .menu: return "Options"
        case .view: return "Create"
        case .share: return "Share"  // DualSense Edge has this, standard doesn't
        case .xbox: return "PS"
        case .leftThumbstick: return "L3"
        case .rightThumbstick: return "R3"
        default: return displayName
        }
    }

    /// Display name for Nintendo controllers (Joy-Con, Pro Controller)
    func displayName(forNintendo isNintendo: Bool) -> String {
        guard isNintendo else { return displayName }
        switch self {
        // macOS maps Nintendo/8BitDo face buttons by LABEL, not position:
        // the button printed "A" reports as buttonA (-> .a), etc. So the
        // A/B/X/Y labels are already correct as-is. What differs from Xbox is
        // the physical ARRANGEMENT of those labels (Nintendo: X north, A east,
        // B south, Y west), which the minimap handles by positioning each
        // button view — not by relabeling.
        case .leftBumper: return "L"
        case .rightBumper: return "R"
        case .leftTrigger: return "ZL"
        case .rightTrigger: return "ZR"
        case .menu: return "+"
        case .view: return "\u{2212}"  // minus sign
        case .share: return "Capture"
        case .xbox: return "Home"
        case .leftThumbstick: return "L Stick"
        case .rightThumbstick: return "R Stick"
        default: return displayName
        }
    }

    /// Display name for 8BitDo pads (Zero 2 / Micro / Lite). Face buttons keep
    /// their printed A/B/X/Y labels (like Nintendo), the bumpers are printed
    /// L/R, but unlike Nintendo the analog/digital triggers are printed L2/R2
    /// (not ZL/ZR), and the guide button is the 8BitDo home button.
    func displayName(forEightBitDo isEightBitDo: Bool) -> String {
        guard isEightBitDo else { return displayName }
        switch self {
        case .leftBumper: return "L"
        case .rightBumper: return "R"
        case .leftTrigger: return "L2"
        case .rightTrigger: return "R2"
        case .xbox: return "Home"
        case .share: return "Star"
        default: return displayName
        }
    }

	/// Display name for Apple TV/Siri Remote controls.
	func displayName(forAppleTVRemote isAppleTVRemote: Bool) -> String {
		guard isAppleTVRemote else { return displayName }
		switch self {
		case .touchpadButton: return "Clickpad Click"
		case .touchpadTap: return "Clickpad Tap"
		case .menu: return "Play/Pause"
		case .view: return "Back"
		case .xbox: return "TV/Home"
		case .siri: return "Siri"
		case .appleTVRemotePower: return "Power"
		case .appleTVRemoteVolumeUp: return "Volume Up"
		case .appleTVRemoteVolumeDown: return "Volume Down"
		case .appleTVRemoteMute: return "Mute"
		default: return displayName
		}
    }

    /// Display name that adapts to any controller type
    func displayName(
		forDualSense isDualSense: Bool,
		forNintendo isNintendo: Bool,
		forAppleTVRemote isAppleTVRemote: Bool = false,
		forEightBitDo isEightBitDo: Bool = false
    ) -> String {
		if isAppleTVRemote { return displayName(forAppleTVRemote: true) }
		if isEightBitDo { return displayName(forEightBitDo: true) }
        if isNintendo { return displayName(forNintendo: true) }
        return displayName(forDualSense: isDualSense)
    }

    /// Short label for compact UI
    var shortLabel: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .leftBumper: return "LB"
        case .rightBumper: return "RB"
        case .leftTrigger: return "LT"
        case .rightTrigger: return "RT"
        case .dpadUp: return "↑"
        case .dpadDown: return "↓"
        case .dpadLeft: return "←"
        case .dpadRight: return "→"
        case .menu: return "≡"
        case .view: return "⧉"
        case .share: return "⬆"
        case .xbox: return "⊗"
		case .siri: return "Siri"
		case .appleTVRemotePower: return "PWR"
		case .appleTVRemoteVolumeUp: return "V+"
		case .appleTVRemoteVolumeDown: return "V-"
		case .appleTVRemoteMute: return "Mute"
        case .leftThumbstick: return "L3"
        case .rightThumbstick: return "R3"
        case .leftStickUp: return "L↑"
        case .leftStickDown: return "L↓"
        case .leftStickLeft: return "L←"
        case .leftStickRight: return "L→"
        case .leftStickUpLeft: return "L↖"
        case .leftStickUpRight: return "L↗"
        case .leftStickDownLeft: return "L↙"
        case .leftStickDownRight: return "L↘"
        case .rightStickUp: return "R↑"
        case .rightStickDown: return "R↓"
        case .rightStickLeft: return "R←"
        case .rightStickRight: return "R→"
        case .rightStickUpLeft: return "R↖"
        case .rightStickUpRight: return "R↗"
        case .rightStickDownLeft: return "R↙"
        case .rightStickDownRight: return "R↘"
        case .touchpadButton: return "TP"
        case .touchpadTwoFingerButton: return "2P"
        case .touchpadTap: return "1T"
        case .touchpadTwoFingerTap: return "2"
        case .micMute: return "🎤"
        case .leftTouchpadButton: return "LP"
        case .rightTouchpadButton: return "RP"
        case .leftTouchpadTap: return "LTp"
        case .rightTouchpadTap: return "RTp"
        case .leftTouchpadRegionTopLeftClick: return "LTL"
        case .leftTouchpadRegionTopRightClick: return "LTR"
        case .leftTouchpadRegionBottomLeftClick: return "LBL"
        case .leftTouchpadRegionBottomRightClick: return "LBR"
        case .leftTouchpadRegionTopLeftTouch: return "LTL"
        case .leftTouchpadRegionTopRightTouch: return "LTR"
        case .leftTouchpadRegionBottomLeftTouch: return "LBL"
        case .leftTouchpadRegionBottomRightTouch: return "LBR"
        case .rightTouchpadRegionTopLeftClick: return "RTL"
        case .rightTouchpadRegionTopRightClick: return "RTR"
        case .rightTouchpadRegionBottomLeftClick: return "RBL"
        case .rightTouchpadRegionBottomRightClick: return "RBR"
        case .rightTouchpadRegionTopLeftTouch: return "RTL"
        case .rightTouchpadRegionTopRightTouch: return "RTR"
        case .rightTouchpadRegionBottomLeftTouch: return "RBL"
        case .rightTouchpadRegionBottomRightTouch: return "RBR"
        // Region buttons fall back to text labels here, but they're rendered
        // by `ButtonIconView` as a custom 2×2 quadrant indicator that's
        // recognizable at a glance (the diagonal-arrow glyphs above looked
        // too similar to each other at button-tile size).
        case .touchpadRegionTopLeftClick: return "TL"
        case .touchpadRegionTopRightClick: return "TR"
        case .touchpadRegionBottomLeftClick: return "BL"
        case .touchpadRegionBottomRightClick: return "BR"
        case .touchpadRegionTopLeftTouch: return "TL"
        case .touchpadRegionTopRightTouch: return "TR"
        case .touchpadRegionBottomLeftTouch: return "BL"
        case .touchpadRegionBottomRightTouch: return "BR"
        case .leftPaddle: return "LP"
        case .rightPaddle: return "RP"
        case .leftFunction: return "LFn"
        case .rightFunction: return "RFn"
        case .xboxPaddle1: return "P1"
        case .xboxPaddle2: return "P2"
        case .xboxPaddle3: return "P3"
        case .xboxPaddle4: return "P4"
        case .gestureTiltBack: return "⤴"
        case .gestureTiltForward: return "⤵"
        case .gestureSteerLeft: return "↰"
        case .gestureSteerRight: return "↱"
        }
    }

    /// Short label appropriate for the controller type
    func shortLabel(forDualSense isDualSense: Bool) -> String {
        guard isDualSense else { return shortLabel }
        switch self {
        case .a: return "✕"
        case .b: return "○"
        case .x: return "□"
        case .y: return "△"
        case .leftBumper: return "L1"
        case .rightBumper: return "R1"
        case .leftTrigger: return "L2"
        case .rightTrigger: return "R2"
        case .menu: return "☰"
        case .view: return "▢"  // Create button symbol
        case .xbox: return "ⓟ"  // PS button
        default: return shortLabel
        }
    }

    /// Short label for Nintendo controllers
    func shortLabel(forNintendo isNintendo: Bool) -> String {
        guard isNintendo else { return shortLabel }
        switch self {
        case .leftBumper: return "L"
        case .rightBumper: return "R"
        case .leftTrigger: return "ZL"
        case .rightTrigger: return "ZR"
        case .menu: return "+"
        case .view: return "\u{2212}"  // minus sign
        case .share: return "\u{25A1}"  // capture button (square)
        case .xbox: return "\u{2302}"   // home button
        default: return shortLabel
        }
    }

    /// Short label for 8BitDo pads: L/R bumpers, L2/R2 triggers (matches the
    /// minimap), everything else falls back to the default labels.
    func shortLabel(forEightBitDo isEightBitDo: Bool) -> String {
        guard isEightBitDo else { return shortLabel }
        switch self {
        case .leftBumper: return "L"
        case .rightBumper: return "R"
        case .leftTrigger: return "L2"
        case .rightTrigger: return "R2"
        default: return shortLabel
        }
    }

    /// Short label for Apple TV/Siri Remote controls.
	func shortLabel(forAppleTVRemote isAppleTVRemote: Bool) -> String {
		guard isAppleTVRemote else { return shortLabel }
		switch self {
		case .touchpadButton: return "Click"
		case .touchpadTap: return "Tap"
		case .menu: return "▶"
		case .view: return "←"
		case .xbox: return "TV"
		case .siri: return "Siri"
		case .appleTVRemotePower: return "PWR"
		case .appleTVRemoteVolumeUp: return "V+"
		case .appleTVRemoteVolumeDown: return "V-"
		case .appleTVRemoteMute: return "Mute"
		default: return shortLabel
		}
    }

    /// Short label that adapts to any controller type
    func shortLabel(
		forDualSense isDualSense: Bool,
		forNintendo isNintendo: Bool,
		forAppleTVRemote isAppleTVRemote: Bool = false
    ) -> String {
		if isAppleTVRemote { return shortLabel(forAppleTVRemote: true) }
        if isNintendo { return shortLabel(forNintendo: true) }
        return shortLabel(forDualSense: isDualSense)
    }
}
