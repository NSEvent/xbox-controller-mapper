import Foundation

extension ControllerButton {
	/// SF Symbol name if available
	var systemImageName: String? {
		systemImageName(forDualSense: false)
	}

	/// SF Symbol name appropriate for the controller type
	func systemImageName(forDualSense isDualSense: Bool) -> String? {
		isDualSense ? dualSenseSystemImageName : xboxSystemImageName
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
			// Custom 2x2 quadrant indicator drawn by ButtonIconView; no
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
}
