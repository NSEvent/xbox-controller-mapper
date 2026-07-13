import Foundation

enum ControllerInputEventQueue {
	case input
	case polling
}

enum ControllerInputEventRouting {
	static func queue(for event: ControllerInputEvent) -> ControllerInputEventQueue {
		switch event {
		case .touchpadMoved,
			 .steamLeftTouchpadMoved,
			 .appleTVRemoteCircularScroll,
			 .touchpadGesture,
			 .touchpadTap,
			 .touchpadTwoFingerTap,
			 .touchpadLongTap,
			 .touchpadTwoFingerLongTap:
			return .polling
		case .buttonPressed,
			 .buttonReleased,
			 .chordDetected,
			 .controllerButtonTap,
			 .touchpadRegionTap,
			 .motionGesture:
			return .input
		}
	}
}
