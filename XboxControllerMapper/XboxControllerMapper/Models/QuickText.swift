import Foundation

/// A quick text snippet that can be typed or run as a terminal command
struct QuickText: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var isTerminalCommand: Bool

    init(text: String = "", isTerminalCommand: Bool = false) {
        self.text = text
        self.isTerminalCommand = isTerminalCommand
    }
}

/// Settings for the on-screen keyboard feature
struct OnScreenKeyboardSettings: Codable {
    var quickTexts: [QuickText] = []
    var defaultTerminalApp: String = "Terminal"  // Bundle name or path
    /// Delay between each character when typing text snippets (in seconds)
    var typingDelay: Double = 0.03  // 30ms default, roughly 33 chars/second

    /// Available terminal apps to choose from
    static let terminalOptions = [
        "Terminal",
        "iTerm",
        "Warp",
        "Alacritty",
        "Kitty",
        "Hyper"
    ]

    /// Typing speed presets
    static let typingSpeedPresets: [(name: String, delay: Double)] = [
        ("Slow", 0.08),       // ~12 chars/sec
        ("Medium", 0.05),     // ~20 chars/sec
        ("Fast", 0.03),       // ~33 chars/sec
        ("Very Fast", 0.015)  // ~66 chars/sec
    ]

    // Custom decoder to handle missing keys from older config files
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quickTexts = try container.decodeIfPresent([QuickText].self, forKey: .quickTexts) ?? []
        defaultTerminalApp = try container.decodeIfPresent(String.self, forKey: .defaultTerminalApp) ?? "Terminal"
        typingDelay = try container.decodeIfPresent(Double.self, forKey: .typingDelay) ?? 0.03
    }

    init(quickTexts: [QuickText] = [], defaultTerminalApp: String = "Terminal", typingDelay: Double = 0.03) {
        self.quickTexts = quickTexts
        self.defaultTerminalApp = defaultTerminalApp
        self.typingDelay = typingDelay
    }

    private enum CodingKeys: String, CodingKey {
        case quickTexts, defaultTerminalApp, typingDelay
    }
}
