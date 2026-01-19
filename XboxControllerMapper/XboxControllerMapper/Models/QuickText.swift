import Foundation

/// An app to show in the on-screen keyboard app bar for quick switching
struct AppBarItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var bundleIdentifier: String
    var displayName: String  // Cached for display when app not installed
}

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
    /// Apps to show in the app bar for quick switching
    var appBarItems: [AppBarItem] = []

    /// Available terminal apps to choose from
    static let terminalOptions = [
        "Terminal",
        "iTerm",
        "Warp",
        "Alacritty",
        "Kitty",
        "Hyper",
        "Tabby",
        "WezTerm",
        "Rio"
    ]

    /// Typing speed presets (0 = paste from clipboard instead of typing)
    static let typingSpeedPresets: [(name: String, delay: Double)] = [
        ("Paste", 0),         // Use clipboard paste (Cmd+V)
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
        appBarItems = try container.decodeIfPresent([AppBarItem].self, forKey: .appBarItems) ?? []
    }

    init(quickTexts: [QuickText] = [], defaultTerminalApp: String = "Terminal", typingDelay: Double = 0.03, appBarItems: [AppBarItem] = []) {
        self.quickTexts = quickTexts
        self.defaultTerminalApp = defaultTerminalApp
        self.typingDelay = typingDelay
        self.appBarItems = appBarItems
    }

    private enum CodingKeys: String, CodingKey {
        case quickTexts, defaultTerminalApp, typingDelay, appBarItems
    }
}
