import CoreGraphics
import Foundation

enum ControllerInputEvent: Equatable {
	case buttonPressed(ControllerButton)
	case buttonReleased(ControllerButton, holdDuration: TimeInterval)
	case chordDetected(Set<ControllerButton>)
	case touchpadMoved(CGPoint)
	case steamLeftTouchpadMoved(CGPoint)
	case appleTVRemoteCircularScroll(CGFloat)
	case touchpadGesture(TouchpadGesture)
	case touchpadTap
	case controllerButtonTap(ControllerButton)
	case touchpadTwoFingerTap
	case touchpadLongTap
	case touchpadTwoFingerLongTap
	case touchpadRegionTap(TouchpadRegion)
	case motionGesture(MotionGestureType)

	var processingQueue: ControllerInputEventQueue {
		switch self {
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

enum ControllerInputEventQueue {
	case input
	case polling
}
