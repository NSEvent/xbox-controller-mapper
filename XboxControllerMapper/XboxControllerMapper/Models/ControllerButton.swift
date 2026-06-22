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

}
