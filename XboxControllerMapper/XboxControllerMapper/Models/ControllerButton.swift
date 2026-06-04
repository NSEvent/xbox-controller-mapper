import Foundation

/// Represents all mappable buttons on Xbox and DualSense controllers
enum ControllerButton: String, Codable, CaseIterable, Identifiable, Sendable {
    // Face buttons
    case a
    case b
    case x
    case y

    // Bumpers
    case leftBumper
    case rightBumper

    // Triggers
    case leftTrigger
    case rightTrigger

    // D-pad
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight

    // Special buttons
    case menu        // Three lines button (≡)
    case view        // Two squares button (⧉)
    case share       // Share/Screenshot button
    case xbox        // Xbox button (center)
    case siri        // Siri/voice button (Apple TV Remote side button)
    case appleTVRemotePower
    case appleTVRemoteVolumeUp
    case appleTVRemoteVolumeDown
    case appleTVRemoteMute

    // Thumbstick clicks
    case leftThumbstick
    case rightThumbstick

    // Joystick custom direction bindings (virtual buttons)
    case leftStickUp
    case leftStickDown
    case leftStickLeft
    case leftStickRight
    case leftStickUpLeft
    case leftStickUpRight
    case leftStickDownLeft
    case leftStickDownRight
    case rightStickUp
    case rightStickDown
    case rightStickLeft
    case rightStickRight
    case rightStickUpLeft
    case rightStickUpRight
    case rightStickDownLeft
    case rightStickDownRight

    // DualSense-specific
    case touchpadButton           // Touchpad click (DualSense only)
    case touchpadTwoFingerButton  // Two-finger touchpad click (DualSense only)
	case touchpadTap              // Single tap on touchpad/touch surface
    case touchpadTwoFingerTap     // Two-finger tap on touchpad (DualSense only)
    case micMute                  // Mic mute button (DualSense only)

    // Steam Controller-specific touchpads
    case leftTouchpadButton       // Left touchpad physical click
    case rightTouchpadButton      // Right touchpad physical click
    case leftTouchpadTap          // Left touchpad tap
    case rightTouchpadTap         // Right touchpad tap

    // Steam Controller-specific touchpad region quadrants. Each pad can split
    // into four regions, and each region has independent click/touch buttons.
    case leftTouchpadRegionTopLeftClick
    case leftTouchpadRegionTopRightClick
    case leftTouchpadRegionBottomLeftClick
    case leftTouchpadRegionBottomRightClick
    case leftTouchpadRegionTopLeftTouch
    case leftTouchpadRegionTopRightTouch
    case leftTouchpadRegionBottomLeftTouch
    case leftTouchpadRegionBottomRightTouch
    case rightTouchpadRegionTopLeftClick
    case rightTouchpadRegionTopRightClick
    case rightTouchpadRegionBottomLeftClick
    case rightTouchpadRegionBottomRightClick
    case rightTouchpadRegionTopLeftTouch
    case rightTouchpadRegionTopRightTouch
    case rightTouchpadRegionBottomLeftTouch
    case rightTouchpadRegionBottomRightTouch

    // Touchpad region quadrants — first-class buttons. Each quadrant has TWO
    // independent buttons: one that fires on physical click and one that fires
    // on touch contact. This lets users assign different actions to touch vs
    // click for the same quadrant (matching the legacy v1 behavior), and lets
    // each binding use the full standard button feature set (long hold, double
    // tap, repeat, layer overrides). PlayStation only.
    case touchpadRegionTopLeftClick
    case touchpadRegionTopRightClick
    case touchpadRegionBottomLeftClick
    case touchpadRegionBottomRightClick
    case touchpadRegionTopLeftTouch
    case touchpadRegionTopRightTouch
    case touchpadRegionBottomLeftTouch
    case touchpadRegionBottomRightTouch

    // DualSense Edge-specific (Pro controller)
    case leftPaddle               // Back paddle, left side (Edge only)
    case rightPaddle              // Back paddle, right side (Edge only)
    case leftFunction             // Front function button, left (Edge only)
    case rightFunction            // Front function button, right (Edge only)

    // Xbox Elite Series 2-specific (4 back paddles)
    case xboxPaddle1              // Back paddle P1 (Elite only)
    case xboxPaddle2              // Back paddle P2 (Elite only)
    case xboxPaddle3              // Back paddle P3 (Elite only)
    case xboxPaddle4              // Back paddle P4 (Elite only)

    // Motion gestures (virtual buttons for logging/stats)
    case gestureTiltBack          // Gyroscope tilt back gesture (DualSense only)
    case gestureTiltForward       // Gyroscope tilt forward gesture (DualSense only)
    case gestureSteerLeft         // Gyroscope steer left gesture (DualSense only)
    case gestureSteerRight        // Gyroscope steer right gesture (DualSense only)

    var id: String { rawValue }

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
        // GameController framework maps Nintendo buttons to match Xbox positions,
        // so A/B/X/Y labels match Xbox (not Nintendo physical layout)
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
		forAppleTVRemote isAppleTVRemote: Bool = false
    ) -> String {
		if isAppleTVRemote { return displayName(forAppleTVRemote: true) }
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

    /// SF Symbol name if available
    var systemImageName: String? {
        systemImageName(forDualSense: false)
    }

    /// SF Symbol name appropriate for the controller type
    func systemImageName(forDualSense isDualSense: Bool) -> String? {
        return isDualSense ? dualSenseSystemImageName : xboxSystemImageName
    }

    private var dualSenseSystemImageName: String? {
        switch self {
        case .dpadUp: return "arrowtriangle.up.fill"
        case .dpadDown: return "arrowtriangle.down.fill"
        case .dpadLeft: return "arrowtriangle.left.fill"
        case .dpadRight: return "arrowtriangle.right.fill"
        case .leftStickUp, .rightStickUp: return "arrow.up.circle"
        case .leftStickDown, .rightStickDown: return "arrow.down.circle"
        case .leftStickLeft, .rightStickLeft: return "arrow.left.circle"
        case .leftStickRight, .rightStickRight: return "arrow.right.circle"
        case .leftStickUpLeft, .rightStickUpLeft: return "arrow.up.left.circle"
        case .leftStickUpRight, .rightStickUpRight: return "arrow.up.right.circle"
        case .leftStickDownLeft, .rightStickDownLeft: return "arrow.down.left.circle"
        case .leftStickDownRight, .rightStickDownRight: return "arrow.down.right.circle"
        case .menu: return "line.3.horizontal"
        case .view: return "square.and.arrow.up"  // Create/Share button (upload icon)
        case .share: return "square.and.arrow.up"
        case .xbox: return "playstation.logo"  // PS button
        case .leftThumbstick: return "l3.button.angledbottom.horizontal.left"
        case .rightThumbstick: return "r3.button.angledbottom.horizontal.right"
        case .touchpadButton: return "hand.point.up.left"
        case .touchpadTwoFingerButton: return nil  // Use text label "2P"
        case .touchpadTap: return "hand.tap"
        case .touchpadTwoFingerTap: return "hand.tap"
        case .micMute: return "mic.slash"
        case .leftTouchpadButton, .rightTouchpadButton: return "hand.point.up.left"
        case .leftTouchpadTap, .rightTouchpadTap: return "hand.tap"
        case .touchpadRegionTopLeftClick, .touchpadRegionTopLeftTouch,
             .touchpadRegionTopRightClick, .touchpadRegionTopRightTouch,
             .touchpadRegionBottomLeftClick, .touchpadRegionBottomLeftTouch,
             .touchpadRegionBottomRightClick, .touchpadRegionBottomRightTouch:
            // Custom 2×2 quadrant indicator drawn by ButtonIconView; no
            // SF Symbol used for these.
            return nil
        case .leftPaddle: return "l.button.roundedbottom.horizontal"
        case .rightPaddle: return "r.button.roundedbottom.horizontal"
        case .leftFunction: return "button.horizontal.top.press"
        case .rightFunction: return "button.horizontal.top.press"
        // Face buttons use text symbols for DualSense, not SF Symbols
        case .a, .b, .x, .y: return nil
        default: return nil
        }
    }

    private var xboxSystemImageName: String? {
        switch self {
        case .dpadUp: return "arrowtriangle.up.fill"
        case .dpadDown: return "arrowtriangle.down.fill"
        case .dpadLeft: return "arrowtriangle.left.fill"
        case .dpadRight: return "arrowtriangle.right.fill"
        case .leftStickUp, .rightStickUp: return "arrow.up.circle"
        case .leftStickDown, .rightStickDown: return "arrow.down.circle"
        case .leftStickLeft, .rightStickLeft: return "arrow.left.circle"
        case .leftStickRight, .rightStickRight: return "arrow.right.circle"
        case .leftStickUpLeft, .rightStickUpLeft: return "arrow.up.left.circle"
        case .leftStickUpRight, .rightStickUpRight: return "arrow.up.right.circle"
        case .leftStickDownLeft, .rightStickDownLeft: return "arrow.down.left.circle"
        case .leftStickDownRight, .rightStickDownRight: return "arrow.down.right.circle"
        case .menu: return "line.3.horizontal"
        case .view: return "rectangle.on.rectangle"
        case .share: return "square.and.arrow.up"
        case .xbox: return "xbox.logo"
        case .siri: return "mic.fill"
        case .appleTVRemotePower: return "power"
        case .appleTVRemoteVolumeUp: return "speaker.wave.3.fill"
        case .appleTVRemoteVolumeDown: return "speaker.wave.1.fill"
        case .appleTVRemoteMute: return "speaker.slash.fill"
        case .leftThumbstick: return "l.circle"
        case .rightThumbstick: return "r.circle"
        case .a: return "a.circle"
        case .b: return "b.circle"
        case .x: return "x.circle"
        case .y: return "y.circle"
        case .touchpadButton: return "hand.point.up.left"
        case .touchpadTap: return "hand.tap"
        case .leftTouchpadButton, .rightTouchpadButton: return "hand.point.up.left"
        case .leftTouchpadTap, .rightTouchpadTap: return "hand.tap"
        case .micMute: return "mic.slash"
        case .xboxPaddle1: return "l.button.roundedbottom.horizontal"
        case .xboxPaddle2: return "r.button.roundedbottom.horizontal"
        case .xboxPaddle3: return "l.button.roundedbottom.horizontal.fill"
        case .xboxPaddle4: return "r.button.roundedbottom.horizontal.fill"
        default: return nil
        }
    }

    /// Category for grouping in UI
    var category: ButtonCategory {
        switch self {
        case .a, .b, .x, .y:
            return .face
        case .leftBumper, .rightBumper:
            return .bumper
        case .leftTrigger, .rightTrigger:
            return .trigger
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight:
            return .dpad
		case .menu, .view, .share, .xbox, .siri,
			 .appleTVRemotePower, .appleTVRemoteVolumeUp,
			 .appleTVRemoteVolumeDown, .appleTVRemoteMute:
            return .special
        case .leftThumbstick, .rightThumbstick:
            return .thumbstick
        case .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
             .leftStickUpLeft, .leftStickUpRight, .leftStickDownLeft, .leftStickDownRight,
             .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
             .rightStickUpLeft, .rightStickUpRight, .rightStickDownLeft, .rightStickDownRight:
            return .thumbstick
        case .touchpadButton, .touchpadTwoFingerButton, .touchpadTap, .touchpadTwoFingerTap, .micMute,
             .leftTouchpadButton, .rightTouchpadButton, .leftTouchpadTap, .rightTouchpadTap,
             .leftTouchpadRegionTopLeftClick, .leftTouchpadRegionTopRightClick,
             .leftTouchpadRegionBottomLeftClick, .leftTouchpadRegionBottomRightClick,
             .leftTouchpadRegionTopLeftTouch, .leftTouchpadRegionTopRightTouch,
             .leftTouchpadRegionBottomLeftTouch, .leftTouchpadRegionBottomRightTouch,
             .rightTouchpadRegionTopLeftClick, .rightTouchpadRegionTopRightClick,
             .rightTouchpadRegionBottomLeftClick, .rightTouchpadRegionBottomRightClick,
             .rightTouchpadRegionTopLeftTouch, .rightTouchpadRegionTopRightTouch,
             .rightTouchpadRegionBottomLeftTouch, .rightTouchpadRegionBottomRightTouch,
             .touchpadRegionTopLeftClick, .touchpadRegionTopRightClick,
             .touchpadRegionBottomLeftClick, .touchpadRegionBottomRightClick,
             .touchpadRegionTopLeftTouch, .touchpadRegionTopRightTouch,
             .touchpadRegionBottomLeftTouch, .touchpadRegionBottomRightTouch:
            return .touchpad  // DualSense-specific buttons
        case .leftPaddle, .rightPaddle, .leftFunction, .rightFunction:
            return .paddle  // DualSense Edge-specific buttons
        case .xboxPaddle1, .xboxPaddle2, .xboxPaddle3, .xboxPaddle4:
            return .paddle  // Xbox Elite-specific buttons
        case .gestureTiltBack, .gestureTiltForward, .gestureSteerLeft, .gestureSteerRight:
            return .touchpad  // DualSense-specific virtual buttons
        }
    }

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

    /// SF Symbol name for Nintendo controllers
    func systemImageName(forNintendo isNintendo: Bool) -> String? {
        guard isNintendo else { return systemImageName }
        switch self {
        case .xbox: return "house"  // Home button
        default: return systemImageName  // Reuse Xbox SF Symbols for everything else
        }
    }

	/// SF Symbol name for Apple TV/Siri Remote controls.
	func systemImageName(forAppleTVRemote isAppleTVRemote: Bool) -> String? {
		guard isAppleTVRemote else { return systemImageName }
		switch self {
		case .touchpadButton:
			return "hand.point.up.left"
		case .touchpadTap:
			return "hand.tap"
		case .menu:
			return "playpause.fill"
		case .view:
			return "chevron.left"
		case .xbox:
			return "tv.fill"
		case .siri:
			return "mic.fill"
		case .appleTVRemotePower:
			return "power"
		case .appleTVRemoteVolumeUp:
			return "plus"
		case .appleTVRemoteVolumeDown:
			return "minus"
		case .appleTVRemoteMute:
			return "speaker.slash.fill"
		case .dpadUp:
			return "chevron.up"
		case .dpadDown:
			return "chevron.down"
		case .dpadLeft:
			return "chevron.left"
		case .dpadRight:
			return "chevron.right"
		default:
			return nil
		}
	}
}

enum ButtonCategory: String, CaseIterable {
    case face
    case bumper
    case trigger
    case dpad
    case special
    case thumbstick
    case touchpad
    case paddle  // DualSense Edge back paddles and function buttons

    var displayName: String {
        switch self {
        case .face: return "Face Buttons"
        case .bumper: return "Bumpers"
        case .trigger: return "Triggers"
        case .dpad: return "D-Pad"
        case .special: return "Special"
        case .thumbstick: return "Thumbsticks"
        case .touchpad: return "Touchpad"
        case .paddle: return "Paddles"
        }
    }

    /// Sort order for chord display: bumpers, triggers, sticks, face, special/touchpad/paddle, dpad
    var chordDisplayOrder: Int {
        switch self {
        case .bumper: return 0
        case .trigger: return 1
        case .thumbstick: return 2
        case .face: return 3
        case .special: return 4
        case .touchpad: return 5
        case .paddle: return 6
        case .dpad: return 7
        }
    }
}
