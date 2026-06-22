import Foundation

extension ControllerButton {
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
			return .touchpad
		case .leftPaddle, .rightPaddle, .leftFunction, .rightFunction:
			return .paddle
		case .xboxPaddle1, .xboxPaddle2, .xboxPaddle3, .xboxPaddle4:
			return .paddle
		case .gestureTiltBack, .gestureTiltForward, .gestureSteerLeft, .gestureSteerRight:
			return .touchpad
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
	case paddle

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
