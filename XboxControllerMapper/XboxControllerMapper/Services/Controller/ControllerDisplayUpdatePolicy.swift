import Foundation
import CoreGraphics

struct ControllerDisplayState: Equatable {
    var leftStick: CGPoint
    var rightStick: CGPoint
    var leftTriggerValue: Float
    var rightTriggerValue: Float
    var displayLeftStick: CGPoint
    var displayRightStick: CGPoint
    var displayLeftTrigger: Float
    var displayRightTrigger: Float
    var displayTouchpadPosition: CGPoint
    var displayTouchpadSecondaryPosition: CGPoint
    var displayIsTouchpadTouching: Bool
    var displayIsTouchpadSecondaryTouching: Bool
}

struct ControllerDisplaySample: Equatable {
    var leftStick: CGPoint
    var rightStick: CGPoint
    var leftTrigger: Float
    var rightTrigger: Float
    var touchpadPosition: CGPoint
    var touchpadSecondaryPosition: CGPoint
    var isTouchpadTouching: Bool
    var isTouchpadSecondaryTouching: Bool
}

enum ControllerDisplayUpdatePolicy {
    static func resolve(
        current: ControllerDisplayState,
        sample: ControllerDisplaySample,
        deadzone: CGFloat
    ) -> ControllerDisplayState {
        var result = current

        // Raw values always track latest samples.
        result.leftStick = sample.leftStick
        result.rightStick = sample.rightStick
        result.leftTriggerValue = sample.leftTrigger
        result.rightTriggerValue = sample.rightTrigger

        if abs(result.displayLeftStick.x - sample.leftStick.x) > deadzone ||
            abs(result.displayLeftStick.y - sample.leftStick.y) > deadzone {
            result.displayLeftStick = sample.leftStick
        }

        if abs(result.displayRightStick.x - sample.rightStick.x) > deadzone ||
            abs(result.displayRightStick.y - sample.rightStick.y) > deadzone {
            result.displayRightStick = sample.rightStick
        }

        if abs(result.displayLeftTrigger - sample.leftTrigger) > Float(deadzone) {
            result.displayLeftTrigger = sample.leftTrigger
        }

        if abs(result.displayRightTrigger - sample.rightTrigger) > Float(deadzone) {
            result.displayRightTrigger = sample.rightTrigger
        }

        if result.displayTouchpadPosition != sample.touchpadPosition {
            result.displayTouchpadPosition = sample.touchpadPosition
        }
        if result.displayTouchpadSecondaryPosition != sample.touchpadSecondaryPosition {
            result.displayTouchpadSecondaryPosition = sample.touchpadSecondaryPosition
        }
        if result.displayIsTouchpadTouching != sample.isTouchpadTouching {
            result.displayIsTouchpadTouching = sample.isTouchpadTouching
        }
        if result.displayIsTouchpadSecondaryTouching != sample.isTouchpadSecondaryTouching {
            result.displayIsTouchpadSecondaryTouching = sample.isTouchpadSecondaryTouching
        }

        return result
    }
}
