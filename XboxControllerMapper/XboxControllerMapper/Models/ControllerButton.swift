import Foundation

/// Represents all mappable buttons on an Xbox controller
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

    var displayName: String {
        switch self {
        case .face: return "Face Buttons"
        case .bumper: return "Bumpers"
        case .trigger: return "Triggers"
        case .dpad: return "D-Pad"
        case .special: return "Special"
        case .thumbstick: return "Thumbsticks"
        }
    }
}
