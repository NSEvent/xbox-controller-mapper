import Foundation

/// A discrete direction that can be emitted by a joystick in Custom mode.
enum JoystickDirection: String, Codable, CaseIterable, Identifiable {
    case up
    case down
    case left
    case right
    case upLeft
    case upRight
    case downLeft
    case downRight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .upLeft: return "Up-Left"
        case .upRight: return "Up-Right"
        case .downLeft: return "Down-Left"
        case .downRight: return "Down-Right"
        }
    }

    var arrowLabel: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .upLeft: return "↖"
        case .upRight: return "↗"
        case .downLeft: return "↙"
        case .downRight: return "↘"
        }
    }

    var isDiagonal: Bool {
        switch self {
        case .upLeft, .upRight, .downLeft, .downRight:
            return true
        case .up, .down, .left, .right:
            return false
        }
    }
}
