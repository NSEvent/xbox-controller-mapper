import Foundation

/// Represents all mappable buttons on Xbox and DualSense controllers
enum ControllerButton: String, Codable, CaseIterable, Identifiable {
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

    // Thumbstick clicks
    case leftThumbstick
    case rightThumbstick

    // DualSense-specific
    case touchpadButton           // Touchpad click (DualSense only)
    case touchpadTwoFingerButton  // Two-finger touchpad click (DualSense only)
    case touchpadTap              // Single tap on touchpad (DualSense only)
    case touchpadTwoFingerTap     // Two-finger tap on touchpad (DualSense only)
    case micMute                  // Mic mute button (DualSense only)

    // DualSense Edge-specific (Pro controller)
    case leftPaddle               // Back paddle, left side (Edge only)
    case rightPaddle              // Back paddle, right side (Edge only)
    case leftFunction             // Front function button, left (Edge only)
    case rightFunction            // Front function button, right (Edge only)

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
        case .leftThumbstick: return "Left Stick"
        case .rightThumbstick: return "Right Stick"
        case .touchpadButton: return "Touchpad Press"
        case .touchpadTwoFingerButton: return "Touchpad 2-Finger Press"
        case .touchpadTap: return "Touchpad Tap"
        case .touchpadTwoFingerTap: return "Touchpad 2-Finger Tap"
        case .micMute: return "Mic Mute"
        case .leftPaddle: return "Left Paddle"
        case .rightPaddle: return "Right Paddle"
        case .leftFunction: return "Left Fn"
        case .rightFunction: return "Right Fn"
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
        case .leftThumbstick: return "L3"
        case .rightThumbstick: return "R3"
        case .touchpadButton: return "TP"
        case .touchpadTwoFingerButton: return "2P"
        case .touchpadTap: return "1T"
        case .touchpadTwoFingerTap: return "2"
        case .micMute: return "🎤"
        case .leftPaddle: return "LP"
        case .rightPaddle: return "RP"
        case .leftFunction: return "LFn"
        case .rightFunction: return "RFn"
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

    /// SF Symbol name if available
    var systemImageName: String? {
        systemImageName(forDualSense: false)
    }

    /// SF Symbol name appropriate for the controller type
    func systemImageName(forDualSense isDualSense: Bool) -> String? {
        if isDualSense {
            switch self {
            case .dpadUp: return "arrowtriangle.up.fill"
            case .dpadDown: return "arrowtriangle.down.fill"
            case .dpadLeft: return "arrowtriangle.left.fill"
            case .dpadRight: return "arrowtriangle.right.fill"
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
            case .leftPaddle: return "l.button.roundedbottom.horizontal"
            case .rightPaddle: return "r.button.roundedbottom.horizontal"
            case .leftFunction: return "button.horizontal.top.press"
            case .rightFunction: return "button.horizontal.top.press"
            // Face buttons use text symbols for DualSense, not SF Symbols
            case .a, .b, .x, .y: return nil
            default: return nil
            }
        } else {
            switch self {
            case .dpadUp: return "arrowtriangle.up.fill"
            case .dpadDown: return "arrowtriangle.down.fill"
            case .dpadLeft: return "arrowtriangle.left.fill"
            case .dpadRight: return "arrowtriangle.right.fill"
            case .menu: return "line.3.horizontal"
            case .view: return "rectangle.on.rectangle"
            case .share: return "square.and.arrow.up"
            case .xbox: return "xbox.logo"
            case .leftThumbstick: return "l.circle"
            case .rightThumbstick: return "r.circle"
            case .a: return "a.circle"
            case .b: return "b.circle"
            case .x: return "x.circle"
            case .y: return "y.circle"
            case .touchpadButton: return "hand.point.up.left"
            case .micMute: return "mic.slash"
            default: return nil
            }
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
        case .menu, .view, .share, .xbox:
            return .special
        case .leftThumbstick, .rightThumbstick:
            return .thumbstick
        case .touchpadButton, .touchpadTwoFingerButton, .touchpadTap, .touchpadTwoFingerTap, .micMute:
            return .touchpad  // DualSense-specific buttons
        case .leftPaddle, .rightPaddle, .leftFunction, .rightFunction:
            return .paddle  // DualSense Edge-specific buttons
        }
    }

    /// Whether this button is only available on PlayStation controllers (DualSense or DualShock)
    var isPlayStationOnly: Bool {
        switch self {
        case .touchpadButton, .touchpadTwoFingerButton, .touchpadTap, .touchpadTwoFingerTap:
            return true  // Available on both DualSense and DualShock
        case .micMute:
            return true  // DualSense only
        case .leftPaddle, .rightPaddle, .leftFunction, .rightFunction:
            return true  // Edge-only, but still PlayStation family
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

    /// Buttons available for Xbox controllers
    static var xboxButtons: [ControllerButton] {
        allCases.filter { !$0.isPlayStationOnly }
    }

    /// Buttons available for DualShock 4 controllers (has touchpad, no mic mute or paddles)
    static var dualShockButtons: [ControllerButton] {
        allCases.filter { !$0.isDualSenseOnly && $0 != .share }
    }

    /// Buttons available for DualSense controllers (excludes Share which doesn't exist on standard DualSense)
    static var dualSenseButtons: [ControllerButton] {
        allCases.filter { $0 != .share && !$0.isDualSenseEdgeOnly }
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
