import Foundation

/// Preset haptic styles for controller action feedback
enum HapticStyle: String, Codable, CaseIterable {
    case lightClick = "lightClick"
    case mediumClick = "mediumClick"
    case heavyClick = "heavyClick"
    case softTap = "softTap"
    case sharpTap = "sharpTap"

    var displayName: String {
        switch self {
        case .lightClick: return "Light Click"
        case .mediumClick: return "Medium Click"
        case .heavyClick: return "Heavy Click"
        case .softTap: return "Soft Tap"
        case .sharpTap: return "Sharp Tap"
        }
    }

    var intensity: Float {
        switch self {
        case .lightClick: return 0.4
        case .mediumClick: return 0.65
        case .heavyClick: return 1.0
        case .softTap: return 0.35
        case .sharpTap: return 0.5
        }
    }

    var sharpness: Float {
        switch self {
        case .lightClick: return 0.8
        case .mediumClick: return 0.7
        case .heavyClick: return 0.6
        case .softTap: return 0.3
        case .sharpTap: return 1.0
        }
    }

    var duration: TimeInterval {
        switch self {
        case .lightClick: return 0.08
        case .mediumClick: return 0.1
        case .heavyClick: return 0.15
        case .softTap: return 0.1
        case .sharpTap: return 0.06
        }
    }
}
