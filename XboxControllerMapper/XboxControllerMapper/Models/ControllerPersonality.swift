import SwiftUI

/// Fun personality types based on controller usage patterns
enum ControllerPersonality: String, Codable, CaseIterable {
    case sharpshooter
    case brawler
    case strategist
    case navigator
    case multitasker
    case minimalist

    var emoji: String {
        switch self {
        case .sharpshooter: return "🎯"
        case .brawler: return "👊"
        case .strategist: return "🧠"
        case .navigator: return "🧭"
        case .multitasker: return "⚡"
        case .minimalist: return "🍃"
        }
    }

    var title: String {
        switch self {
        case .sharpshooter: return "Sharpshooter"
        case .brawler: return "Brawler"
        case .strategist: return "Strategist"
        case .navigator: return "Navigator"
        case .multitasker: return "Multitasker"
        case .minimalist: return "Minimalist"
        }
    }

    var tagline: String {
        switch self {
        case .sharpshooter: return "Trigger-happy and precision-focused"
        case .brawler: return "All about the face buttons"
        case .strategist: return "Master of combos and complex inputs"
        case .navigator: return "D-pad devotee, menu master"
        case .multitasker: return "Uses everything, masters all"
        case .minimalist: return "Less is more, every press counts"
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .sharpshooter: return [Color(red: 1.0, green: 0.3, blue: 0.2), Color(red: 1.0, green: 0.6, blue: 0.1)]
        case .brawler: return [Color(red: 0.8, green: 0.1, blue: 0.4), Color(red: 0.5, green: 0.1, blue: 0.8)]
        case .strategist: return [Color(red: 0.1, green: 0.4, blue: 0.9), Color(red: 0.3, green: 0.8, blue: 0.9)]
        case .navigator: return [Color(red: 0.1, green: 0.7, blue: 0.4), Color(red: 0.2, green: 0.9, blue: 0.7)]
        case .multitasker: return [Color(red: 0.9, green: 0.5, blue: 0.0), Color(red: 1.0, green: 0.8, blue: 0.0)]
        case .minimalist: return [Color(red: 0.4, green: 0.4, blue: 0.5), Color(red: 0.7, green: 0.7, blue: 0.8)]
        }
    }
}
