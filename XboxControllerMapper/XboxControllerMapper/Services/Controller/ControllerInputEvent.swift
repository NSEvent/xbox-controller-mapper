import Foundation
import CoreGraphics

/// Unified event type for all controller inputs.
/// Replaces 12 separate callback closures with a single typed event stream.
enum ControllerInputEvent: Equatable {
    // Discrete button events
    case buttonPressed(ControllerButton)
    case buttonReleased(ControllerButton, holdDuration: TimeInterval)
    case chord(buttons: Set<ControllerButton>)

    // Touchpad events
    case touchpadMoved(delta: CGPoint)
    case touchpadGesture(TouchpadGesture)
    case touchpadTap
    case touchpadTwoFingerTap
    case touchpadLongTap
    case touchpadTwoFingerLongTap

    // Motion events
    case motionGesture(MotionGestureType)
}
